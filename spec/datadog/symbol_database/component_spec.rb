# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/extractor'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/uploader'

RSpec.describe Datadog::SymbolDatabase::Component do
  # Use a real Settings instance — Settings uses dynamic DSL methods (via
  # Core::Configuration::Options) that instance_double can't verify.
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.symbol_database.internal.force_upload = false
      s.remote.enabled = true
      s.service = 'test-service'
      s.env = 'test'
      s.version = '1.0'
    end
  end

  let(:agent_settings) do
    instance_double(
      Datadog::Core::Configuration::AgentSettings,
      hostname: 'localhost',
      port: 8126,
      timeout_seconds: 30,
      ssl: false,
    )
  end

  let(:raw_logger) { instance_double(Logger, debug: nil) }
  let(:logger) { Datadog::SymbolDatabase::Logger.new(settings, raw_logger) }

  # Stub Uploader and ScopeBatcher to avoid real HTTP calls.
  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:symbols).and_return(
      instance_double(Datadog::SymbolDatabase::Transport::Symbols::Transport)
    )
    allow(Datadog::SymbolDatabase::ScopeBatcher).to receive(:new).and_return(
      instance_double(Datadog::SymbolDatabase::ScopeBatcher, shutdown: nil, add_scope: nil, flush: nil, reset: nil)
    )
  end

  # Make the debounce window short so tests don't wait 5s.
  # 0.05s gives the scheduler thread time to enter its wait loop and fire.
  before { stub_const('Datadog::SymbolDatabase::Component::EXTRACT_DEBOUNCE_INTERVAL', 0.05) }

  describe '.environment_supported?', :symdb_supported_platforms do
    it 'returns true on MRI Ruby 2.6+' do
      stub_const('RUBY_ENGINE', 'ruby')
      stub_const('RUBY_VERSION', '3.2.0')
      stub_const('Datadog::RubyVersion::CURRENT_RUBY_VERSION', Gem::Version.new(RUBY_VERSION))
      expect(described_class.send(:environment_supported?, logger)).to be true
    end

    it 'returns false and logs on JRuby' do
      stub_const('RUBY_ENGINE', 'jruby')
      expect(raw_logger).to receive(:debug) { |&block| expect(block.call).to match(/not supported on jruby/) }
      expect(described_class.send(:environment_supported?, logger)).to be false
    end

    it 'returns false and logs on Ruby < 2.6' do
      stub_const('RUBY_ENGINE', 'ruby')
      stub_const('RUBY_VERSION', '2.5.0')
      stub_const('Datadog::RubyVersion::CURRENT_RUBY_VERSION', Gem::Version.new(RUBY_VERSION))
      expect(raw_logger).to receive(:debug) { |&block| expect(block.call).to match(/requires Ruby 2.6\+/) }
      expect(described_class.send(:environment_supported?, logger)).to be false
    end
  end

  describe '.build' do
    context 'when symbol_database is disabled' do
      before { settings.symbol_database.enabled = false }

      it 'returns nil' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_nil
      end
    end

    context 'when remote is disabled and force_upload is false' do
      before do
        settings.remote.enabled = false
        settings.symbol_database.internal.force_upload = false
      end

      it 'returns nil' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_nil
      end
    end

    context 'when remote is enabled' do
      before { settings.remote.enabled = true }

      it 'returns a Component' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_a(described_class)
      end
    end

    context 'when force_upload is enabled' do
      before { settings.symbol_database.internal.force_upload = true }

      it 'returns a Component' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_a(described_class)
        result.shutdown!
      end

      it 'calls schedule_deferred_upload' do
        expect_any_instance_of(described_class).to receive(:schedule_deferred_upload)
        described_class.build(settings, agent_settings, logger)
      end
    end

    context 'without force_upload' do
      it 'does not call schedule_deferred_upload' do
        expect_any_instance_of(described_class).not_to receive(:schedule_deferred_upload)
        described_class.build(settings, agent_settings, logger)
      end
    end
  end

  describe '#schedule_deferred_upload' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    context 'without Rails' do
      before do
        hide_const('ActiveSupport')
        hide_const('Rails::Railtie')
      end

      it 'calls start_upload immediately' do
        expect(component).to receive(:start_upload)
        component.schedule_deferred_upload
      end
    end

    context 'with Rails detected' do
      let(:after_init_callbacks) { [] }

      before do
        active_support_mod = Module.new do
          def self.on_load(_name, &block)
          end
        end
        stub_const('ActiveSupport', active_support_mod)
        stub_const('Rails::Railtie', Class.new)

        # Provide Rails.application.config.eager_load so the auto-deferred
        # upload runs in this test (production-like config). stub_const
        # replaces the Rails module entirely.
        rails_config = Struct.new(:eager_load).new(true)
        rails_app = Struct.new(:config).new(rails_config)
        rails_module = Module.new
        rails_module.define_singleton_method(:application) { rails_app }
        stub_const('Rails', rails_module)
        stub_const('Rails::Railtie', Class.new)

        allow(::ActiveSupport).to receive(:on_load).with(:after_initialize) do |&block|
          after_init_callbacks << block
        end
      end

      it 'defers start_upload to ActiveSupport.on_load(:after_initialize)' do
        expect(component).not_to receive(:start_upload)
        component.schedule_deferred_upload
        expect(after_init_callbacks.size).to eq(1)
      end

      it 'callback triggers start_upload on the registering Component' do
        component.schedule_deferred_upload
        expect(component).to receive(:start_upload)
        after_init_callbacks.each(&:call)
      end

      it 'each Component registers its own callback (no class-level dedup of registration)' do
        # Per-instance design: each Component schedules its own deferred upload.
        # Old shut-down Components short-circuit their start_upload via @shutdown,
        # so the surviving Component is the one that actually triggers extraction.
        component2 = described_class.new(settings, agent_settings, logger)

        component.schedule_deferred_upload
        component2.schedule_deferred_upload

        expect(after_init_callbacks.size).to eq(2)

        component2.shutdown!
      end
    end
  end

  describe '#start_upload (debounced extraction)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'eventually triggers extract_and_upload after the debounce window' do
      expect(component).to receive(:extract_and_upload).and_call_original
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])

      component.start_upload
      expect(component.wait_for_idle(timeout: 5)).to be true
    end

    it 'coalesces multiple start_upload calls into a single extraction (debounce)' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      5.times { component.start_upload }
      component.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(1)
    end

    it 'does not extract when shut down' do
      component.shutdown!
      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
    end

    it 'sets last_upload_time and last_upload_scope_count after a successful upload' do
      file_scope1 = instance_double(Datadog::SymbolDatabase::Scope, scope_type: 'FILE', name: 'a.rb', scopes: [])
      file_scope2 = instance_double(Datadog::SymbolDatabase::Scope, scope_type: 'FILE', name: 'b.rb', scopes: [])
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_yield(file_scope1).and_yield(file_scope2)
      allow(component.instance_variable_get(:@scope_batcher)).to receive(:add_scope)
      allow(component.instance_variable_get(:@scope_batcher)).to receive(:flush)

      expect(component.last_upload_time).to be_nil
      expect(component.last_upload_scope_count).to be_nil

      component.start_upload
      component.wait_for_idle(timeout: 5)

      expect(component.last_upload_time).to be_a(Time)
      expect(component.last_upload_scope_count).to eq(2)
    end
  end

  describe '#wait_for_idle' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'returns true when an upload completes within the timeout' do
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])
      component.start_upload
      expect(component.wait_for_idle(timeout: 5)).to be true
    end

    it 'returns false when no upload happens within the timeout' do
      expect(component.wait_for_idle(timeout: 0.1)).to be false
    end
  end

  describe '#shutdown!' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    it 'sets the shutdown flag' do
      component.shutdown!
      expect(component.shutdown?).to be true
    end

    it 'prevents subsequent start_upload from extracting' do
      component.shutdown!
      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
      # start_upload enters the scheduler mutex, sees @shutdown=true, and returns
      # without starting a scheduler thread. Nothing to wait on.
      expect(component.instance_variable_get(:@scheduler_thread)).to be_nil
    end

    it 'cancels a pending debounced extraction' do
      extractor = component.instance_variable_get(:@extractor)
      expect(extractor).not_to receive(:extract_all)

      component.start_upload
      # shutdown! sets @shutdown=true, signals the scheduler CV, and joins the
      # thread. By the time shutdown! returns, the scheduler thread has woken,
      # seen @shutdown=true, and exited without calling extract_all.
      component.shutdown!
      expect(component.instance_variable_get(:@scheduler_thread)).to be_nil
    end

    it 'prevents a post-shutdown class definition from enqueuing into the hot-load buffer' do
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])
      component.start_upload
      component.wait_for_idle(timeout: 5)

      buffer = component.instance_variable_get(:@hot_load_buffer)
      tracepoint = component.instance_variable_get(:@hot_load_tracepoint)
      expect(tracepoint).not_to be_nil
      expect(tracepoint.enabled?).to be true

      component.shutdown!

      expect(tracepoint.enabled?).to be false
      expect(component.instance_variable_get(:@hot_load_tracepoint)).to be_nil

      begin
        # Define a class after shutdown! — with the TracePoint disabled this
        # must not enqueue into the hot-load buffer. A regression here means
        # an enabled TracePoint leaked past shutdown! and is rooted by the VM,
        # growing the buffer unboundedly for the rest of the process.
        before_size = buffer.size
        eval('class SymdbShutdownSpecPostShutdownClass; def hello; end; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
        expect(buffer.size).to eq(before_size)
      ensure
        Object.send(:remove_const, :SymdbShutdownSpecPostShutdownClass) if Object.const_defined?(:SymdbShutdownSpecPostShutdownClass)
      end
    end

    it 'waits for an in-flight extraction to complete' do
      events = Queue.new
      extract_started = Queue.new
      release_extract = Queue.new

      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extract_started.push(:started)
        release_extract.pop
        events.push(:extract_returned)
        []
      end

      component.start_upload
      extract_started.pop  # extraction is in flight; @upload_in_progress is true

      shutdown_thread = Thread.new do
        component.shutdown!
        events.push(:shutdown_returned)
      end

      release_extract.push(:go)
      shutdown_thread.join(10)

      # shutdown! must not return until the in-flight extraction completes
      expect(events.pop).to eq(:extract_returned)
      expect(events.pop).to eq(:shutdown_returned)
      expect(component.upload_in_progress).to be false
    end

    context 'when called from a forked child that inherited @upload_in_progress=true' do
      # When a process that has a configured Component forks, the child
      # inherits the @upload_in_progress flag as a stale snapshot — the
      # scheduler thread that would clear it lives only in the parent. If
      # the child's at_exit hook (which calls Datadog.shutdown!) reaches the
      # cv wait, it blocks for the full 5s timeout for no benefit, since
      # nothing in the child can ever signal the cv.
      #
      # The PID-mismatch guard in shutdown! detects this case and clears the
      # stale flag without waiting. Verified by simulating the PID mismatch
      # via stub_const on Process.pid — direct, hermetic, no fork required.
      it 'detects PID mismatch and returns without waiting on the cv' do
        component.instance_variable_set(:@upload_in_progress, true)
        # Simulate the child observing a different PID than the one captured
        # at Component construction in the parent.
        original_pid = component.instance_variable_get(:@owner_pid)
        allow(Process).to receive(:pid).and_return(original_pid + 1)

        # @upload_in_progress_cv must not be touched in the child branch —
        # the cv has no signaler in the child, so any wait would burn its
        # full timeout.
        cv = component.instance_variable_get(:@upload_in_progress_cv)
        expect(cv).not_to receive(:wait)

        component.shutdown!

        # @owner_pid is unchanged — the guard treats the inherited flag as a
        # stale snapshot rather than claiming ownership for the child.
        expect(component.instance_variable_get(:@owner_pid)).to eq(original_pid)
        expect(component.upload_in_progress).to be false
        expect(component.shutdown?).to be true
      end

      it 'still waits on the cv when called from the owning process' do
        # Counterpart to the PID-mismatch test above: confirms the guard does
        # not short-circuit in the normal (non-forked) case. Without this,
        # the guard could silently degrade the in-flight-extraction wait.
        component.instance_variable_set(:@upload_in_progress, true)
        # Don't stub Process.pid — same-process case.

        cv = component.instance_variable_get(:@upload_in_progress_cv)
        # The cv will receive #wait. We make it terminate immediately so the
        # test doesn't take 5s; we're only asserting the call happens.
        allow(cv).to receive(:wait) do |mutex, _timeout|
          # Match the contract of ConditionVariable#wait: clear the predicate
          # so shutdown! sees @upload_in_progress=false after.
          component.instance_variable_set(:@upload_in_progress, false)
        end
        expect(cv).to receive(:wait).with(component.instance_variable_get(:@mutex), 5)

        component.shutdown!
      end

      it 'waits on the cv for child-owned uploads (start_upload called in this process)' do
        # Codex review scenario: in preload/fork servers the child can call
        # start_upload on the inherited Component (e.g. remote config arrives
        # in a Puma worker). The resulting upload is child-owned and must not
        # be discarded by the PID-mismatch guard. start_upload claims
        # @owner_pid for the current process, so shutdown! takes the cv-wait
        # branch and waits for the child's extraction to finish.
        original_owner_pid = component.instance_variable_get(:@owner_pid)
        child_pid = original_owner_pid + 1
        allow(Process).to receive(:pid).and_return(child_pid)

        extract_started = Queue.new
        release_extract = Queue.new
        allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
          extract_started.push(:started)
          release_extract.pop
          []
        end

        component.start_upload
        extract_started.pop # extraction in flight; @upload_in_progress=true; child owns it

        # start_upload must have claimed ownership for the simulated child pid.
        expect(component.instance_variable_get(:@owner_pid)).to eq(child_pid)

        shutdown_thread = Thread.new { component.shutdown! }
        release_extract.push(:go) # let extraction complete; cv will be signaled
        joined = shutdown_thread.join(10)
        expect(joined).not_to be_nil # shutdown! returned within 10s

        expect(component.upload_in_progress).to be false
        expect(component.shutdown?).to be true
      end

      it 'clears inherited @upload_in_progress when child calls start_upload' do
        # If the parent had @upload_in_progress=true at fork time and the
        # child later calls start_upload, the inherited true is a stale
        # snapshot — the parent's scheduler does not exist in the child.
        # Without clearing it on ownership claim, the child's shutdown! could
        # cv-wait on a flag nothing in this process will ever clear.
        original_owner_pid = component.instance_variable_get(:@owner_pid)
        child_pid = original_owner_pid + 1
        allow(Process).to receive(:pid).and_return(child_pid)

        component.instance_variable_set(:@upload_in_progress, true)

        # Hold the scheduler in its wait so extract_and_upload doesn't run
        # before we check the post-claim state.
        allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])

        component.start_upload

        expect(component.instance_variable_get(:@owner_pid)).to eq(child_pid)
        # The inherited stale flag is cleared at ownership claim time, before
        # the scheduler thread runs.
        # (The scheduler may set it again on its own — that's the legitimate
        # child-owned case.)

        component.shutdown!
      end
    end
  end

  describe '#after_fork!' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    # Simulate fork: call after_fork! on the same Component to model the
    # state a child process inherits. Real fork specs are awkward in
    # rspec — the unit-level guarantees are about mutex/CV/thread reinit
    # and force-upload re-trigger, which are observable without forking.

    it 'reinitializes scheduler mutex and condition variable' do
      old_mutex = component.instance_variable_get(:@scheduler_mutex)
      old_cv = component.instance_variable_get(:@scheduler_cv)

      component.after_fork!

      expect(component.instance_variable_get(:@scheduler_mutex)).not_to equal(old_mutex)
      expect(component.instance_variable_get(:@scheduler_cv)).not_to equal(old_cv)
    end

    it 'reinitializes the upload mutex, condition variables, and hot-load buffer mutex' do
      old_mutex = component.instance_variable_get(:@mutex)
      old_progress_cv = component.instance_variable_get(:@upload_in_progress_cv)
      old_last_upload_cv = component.instance_variable_get(:@last_upload_time_cv)
      old_buffer_mutex = component.instance_variable_get(:@hot_load_buffer_mutex)

      component.after_fork!

      expect(component.instance_variable_get(:@mutex)).not_to equal(old_mutex)
      expect(component.instance_variable_get(:@upload_in_progress_cv)).not_to equal(old_progress_cv)
      expect(component.instance_variable_get(:@last_upload_time_cv)).not_to equal(old_last_upload_cv)
      expect(component.instance_variable_get(:@hot_load_buffer_mutex)).not_to equal(old_buffer_mutex)
    end

    it 'clears scheduler thread reference and pending schedule' do
      # start_upload assigns @scheduler_thread synchronously inside
      # @scheduler_mutex via ensure_scheduler_thread, so the ivar is non-nil
      # by the time start_upload returns — no wait needed. Capture the
      # thread reference before after_fork! nils it so we can terminate it
      # in the ensure block below.
      component.start_upload
      scheduler_thread = component.instance_variable_get(:@scheduler_thread)
      expect(scheduler_thread).not_to be_nil

      component.after_fork!

      expect(component.instance_variable_get(:@scheduler_thread)).to be_nil
      expect(component.instance_variable_get(:@scheduled_at)).to be_nil
      expect(component.instance_variable_get(:@scheduler_signaled)).to be false
    ensure
      # In a real fork, the kernel destroys the parent's scheduler thread in
      # the child, so the after_fork! contract assumes the underlying thread
      # is already gone. Simulating fork by calling after_fork! on the parent
      # in-process leaves the scheduler thread alive and orphaned: it's
      # bound by closure to the pre-after_fork! @scheduler_mutex /
      # @scheduler_cv, which nothing else references — it would block in
      # scheduler_loop's @scheduler_cv.wait forever. shutdown! cannot clean
      # it up (it acts on the post-after_fork! mutex/cv and the now-nil
      # @scheduler_thread). Kill the captured reference directly so the
      # leak detector doesn't report it across subsequent examples.
      scheduler_thread&.kill
      scheduler_thread&.join(5)
    end

    it 'clears the hot-load buffer and the initial-extraction flag' do
      component.instance_variable_get(:@hot_load_buffer) << Object
      component.instance_variable_set(:@initial_extraction_done, true)

      component.after_fork!

      expect(component.instance_variable_get(:@hot_load_buffer)).to be_empty
      expect(component.instance_variable_get(:@initial_extraction_done)).to be false
    end

    it 'clears the hot-load tracepoint reference so start_upload installs a fresh one' do
      tracepoint = TracePoint.new(:class) {}
      component.instance_variable_set(:@hot_load_tracepoint, tracepoint)

      component.after_fork!

      expect(component.instance_variable_get(:@hot_load_tracepoint)).to be_nil
    end

    it 'disables the inherited hot-load tracepoint before clearing the reference' do
      # In a forked child, the parent's enabled TracePoint is copied in and
      # remains rooted by the VM. Niling the ivar without disabling first would
      # leave it firing — and a subsequent start_upload would install a second
      # hook on top of it, double-enqueueing every class load.
      tracepoint = TracePoint.new(:class) {}
      tracepoint.enable
      component.instance_variable_set(:@hot_load_tracepoint, tracepoint)
      expect(tracepoint.enabled?).to be true

      component.after_fork!

      expect(tracepoint.enabled?).to be false
      expect(component.instance_variable_get(:@hot_load_tracepoint)).to be_nil
    end

    it 'resets @upload_in_progress to false' do
      component.instance_variable_set(:@upload_in_progress, true)

      component.after_fork!

      expect(component.upload_in_progress).to be false
    end

    it 'replaces the scope batcher so the child does not inherit the parent uploaded-scopes dedup set' do
      # ScopeBatcher#add_scope skips scopes whose name is already in @uploaded_modules.
      # Without a fresh batcher, the child's re-extraction silently drops every scope
      # name the parent already uploaded.
      # Re-stub ScopeBatcher.new so each call yields a distinct double instead of
      # the single fixed double in the outer `before` block.
      allow(Datadog::SymbolDatabase::ScopeBatcher).to receive(:new) do
        instance_double(Datadog::SymbolDatabase::ScopeBatcher, shutdown: nil, add_scope: nil, flush: nil, reset: nil)
      end
      old_batcher = component.instance_variable_get(:@scope_batcher)

      component.after_fork!

      expect(component.instance_variable_get(:@scope_batcher)).not_to equal(old_batcher)
    end

    context 'when force_upload is enabled' do
      before do
        allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
        hide_const('ActiveSupport')
        hide_const('Rails::Railtie')
      end

      it 're-registers the deferred upload in the child' do
        expect(component).to receive(:schedule_deferred_upload)
        component.after_fork!
      end
    end

    context 'when force_upload is not enabled' do
      it 'does not re-trigger an upload — relies on remote config re-subscription' do
        expect(component).not_to receive(:schedule_deferred_upload)
        component.after_fork!
      end
    end

    it 'leaves a child Component able to start_upload normally after fork-state reset' do
      # Simulate parent upload completing, then fork.
      component.instance_variable_set(:@last_upload_time, Datadog::Core::Utils::Time.now)
      component.after_fork!

      extractor = component.instance_variable_get(:@extractor)
      expect(extractor).to receive(:extract_all).at_least(:once).and_return([])

      component.start_upload
      expect(component.wait_for_idle(timeout: 5)).to be true

      component.shutdown!
    end
  end

  describe 'debounce regression (collapses bursts of start_upload calls)' do
    # The two-uploads bug was that a burst of start_upload triggers — auto-deferred
    # callback then explicit script call — produced two extractions. The fix is
    # the per-instance debounce scheduler: multiple start_upload calls within
    # EXTRACT_DEBOUNCE_INTERVAL coalesce into a single extraction.
    before do
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
      hide_const('ActiveSupport')
      hide_const('Rails::Railtie')
    end

    it 'each Component built across reconfigurations extracts independently' do
      # With hot-load coverage, dedup across Components is intentionally removed.
      # Each Component is responsible for its own initial extraction (which the
      # new Component needs in order to have a hot-load baseline) plus any
      # incremental extractions driven by the TracePoint :class hook.
      extraction_count = 0
      allow_any_instance_of(described_class).to receive(:extract_and_upload) do |_inst|
        extraction_count += 1
      end

      component_a = described_class.build(settings, agent_settings, logger)
      component_a.wait_for_idle(timeout: 5)
      component_a.shutdown!

      component_b = described_class.build(settings, agent_settings, logger)
      component_b.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(2)

      component_b.shutdown!
    end
  end

  describe 'hot-load coverage (TracePoint :class)' do
    # Verifies the cross-tracer parity goal (Java ClassFileTransformer,
    # Python BaseModuleWatchdog#after_import, .NET AppDomain.AssemblyLoad):
    # classes defined after initial extraction reach the symbol DB via
    # incremental uploads driven by the TracePoint :class hook.
    before do
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
      hide_const('ActiveSupport')
      hide_const('Rails::Railtie')
    end

    it 'extracts a class defined after the initial upload completes' do
      # REPRODUCER (do not merge): force extract_all to sleep 12s — longer than the
      # combined budget of both wait_for_idle(timeout: 5) calls. The first wait_for_idle
      # times out at T=5s; the test ignores the return value and proceeds. The second
      # wait_for_idle starts with start_time = @last_upload_time = nil (initial extract
      # is still sleeping) and also times out — but the test ignores that too and asserts
      # on extracted_modules, which is empty because the hot-load extract pass has not
      # had a chance to run. This forces the race that on macOS-15 Ruby 3.2 surfaced
      # naturally because the initial extract_all over ObjectSpace ran long enough to
      # blow past the 5s timeout.
      allow_any_instance_of(Datadog::SymbolDatabase::Extractor).to receive(:extract_all) { sleep 12 }
      extracted_modules = []
      allow_any_instance_of(Datadog::SymbolDatabase::Extractor).to receive(:extract) do |_inst, mod|
        extracted_modules << mod
        nil
      end

      component = described_class.build(settings, agent_settings, logger)
      component.wait_for_idle(timeout: 5)

      begin
        # Define a class — `class Foo` opens a class body, which fires
        # TracePoint :class. The hook buffers the class; the scheduler
        # drains and calls Extractor#extract.
        eval('class SymdbHotLoadSpecNewClass; def hello; end; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval

        component.wait_for_idle(timeout: 5)

        expect(extracted_modules.map(&:name)).to include('SymdbHotLoadSpecNewClass')
      ensure
        Object.send(:remove_const, :SymdbHotLoadSpecNewClass) if Object.const_defined?(:SymdbHotLoadSpecNewClass)
        component.shutdown!
      end
    end

    it 'does not raise inside the :class hook when user code overrides singleton_class? with an incompatible signature' do
      # Define a top-level class whose `self.singleton_class?(arg)` override would
      # raise ArgumentError if the hook dispatched through it. The hook must use
      # the cached unbound Module#singleton_class? predicate instead.
      eval(<<~RUBY, binding, __FILE__, __LINE__ + 1) # rubocop:disable Security/Eval
        class SymdbHotLoadSpecSingletonOverride
          def self.singleton_class?(_arg)
            raise 'hot-load hook should not dispatch through user-defined singleton_class?'
          end
        end
      RUBY

      component = described_class.build(settings, agent_settings, logger)
      component.wait_for_idle(timeout: 5)

      buffered = nil
      begin
        # Reopen the class with the override already in place. The :class TracePoint
        # fires; the hook must filter via the unbound predicate without raising.
        expect do
          eval('class SymdbHotLoadSpecSingletonOverride; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
        end.not_to raise_error

        buffered = component.instance_variable_get(:@hot_load_buffer).dup
      ensure
        component.shutdown!
        Object.send(:remove_const, :SymdbHotLoadSpecSingletonOverride) if Object.const_defined?(:SymdbHotLoadSpecSingletonOverride)
      end

      # The reopened class is a regular Class (not a singleton class), so the
      # bound Module#singleton_class? returns false and the module is enqueued.
      expect(buffered.map(&:name)).to include('SymdbHotLoadSpecSingletonOverride')
    end

    it 'rescues exceptions raised inside the :class hook so customer class loads do not break' do
      # The :class TracePoint fires inside the customer's `class Foo; ... end`
      # body. If an exception escapes the callback, it propagates into the
      # class definition and breaks the customer's class load (verified
      # empirically: backtrace includes `<class:CustomerClass>`). The rescue
      # in install_hot_load_hook contains the failure, logs at debug, and
      # reports via telemetry.
      component = described_class.build(settings, agent_settings, logger)
      component.wait_for_idle(timeout: 5)

      injected_error = RuntimeError.new('simulated hot-load enqueue failure')
      allow(component).to receive(:enqueue_hot_load).and_raise(injected_error)

      expect(raw_logger).to receive(:debug) do |&block|
        expect(block.call).to include('hot-load hook error', 'RuntimeError', 'simulated hot-load enqueue failure')
      end

      begin
        # With the rescue in place, defining a class while enqueue_hot_load is
        # rigged to raise must not propagate the exception into the class body.
        expect do
          eval('class SymdbHotLoadRescueTestClass; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
        end.not_to raise_error
      ensure
        component.shutdown!
        Object.send(:remove_const, :SymdbHotLoadRescueTestClass) if Object.const_defined?(:SymdbHotLoadRescueTestClass)
      end
    end

    it 'does not propagate exceptions when logger.debug itself raises' do
      # If the rescue handler's own logger call raises (custom logger
      # implementation, IO error), it would escape the outer rescue and
      # surface in the customer's class body. The inner rescue contains
      # this case.
      component = described_class.build(settings, agent_settings, logger)
      component.wait_for_idle(timeout: 5)

      allow(component).to receive(:enqueue_hot_load)
        .and_raise(RuntimeError.new('simulated hot-load enqueue failure'))
      allow(raw_logger).to receive(:debug).and_raise(RuntimeError.new('logger boom'))

      begin
        expect do
          eval('class SymdbHotLoadLoggerRescueTestClass; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
        end.not_to raise_error
      ensure
        component.shutdown!
        Object.send(:remove_const, :SymdbHotLoadLoggerRescueTestClass) if Object.const_defined?(:SymdbHotLoadLoggerRescueTestClass)
      end
    end
  end

  describe 'enable/disable upload (ported from Java SymDBEnablementTest.enableDisableSymDBThroughRC)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'extracts once when start_upload is called' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      component.start_upload
      component.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(1)
    end

    it 'stop_upload cancels a pending debounce so no extraction occurs' do
      extractor = component.instance_variable_get(:@extractor)
      expect(extractor).not_to receive(:extract_all)

      component.start_upload
      component.stop_upload
      # stop_upload clears @scheduled_at and signals the scheduler CV.
      # The scheduler thread (if started) wakes, sees @scheduled_at=nil, and
      # returns to indefinite wait. extract_all is not called. The `after`
      # block's shutdown! will join the thread before RSpec verifies the
      # `not_to receive` expectation.
      expect(component.instance_variable_get(:@scheduled_at)).to be_nil
    end

    it 're-runs extract_all after stop_upload + start_upload (RC re-enable does a fresh scan)' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      component.start_upload
      component.wait_for_idle(timeout: 5)
      component.stop_upload
      # stop_upload disables the hot-load hook and resets @initial_extraction_done.
      # A subsequent start_upload — modeling RC re-enabling symdb — therefore
      # runs a fresh extract_all rather than draining an empty hot-load buffer.
      component.start_upload
      component.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(2)
    end

    it 'stop_upload disables the hot-load TracePoint and clears the buffer' do
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])
      component.start_upload
      component.wait_for_idle(timeout: 5)

      component.instance_variable_get(:@hot_load_buffer) << Object # simulate a queued event
      tracepoint = component.instance_variable_get(:@hot_load_tracepoint)
      expect(tracepoint).not_to be_nil
      expect(tracepoint.enabled?).to be true

      component.stop_upload

      expect(tracepoint.enabled?).to be false
      expect(component.instance_variable_get(:@hot_load_tracepoint)).to be_nil
      expect(component.instance_variable_get(:@hot_load_buffer)).to be_empty
      expect(component.instance_variable_get(:@initial_extraction_done)).to be false
    end

    it 'stop_upload prevents a post-stop class definition from triggering extraction' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      component.start_upload
      component.wait_for_idle(timeout: 5)
      expect(extraction_count).to eq(1)

      component.stop_upload

      begin
        # Define a class after stop_upload — with the TracePoint disabled this
        # must not enqueue a hot-load event or re-arm the scheduler. The
        # @scheduled_at check is the structural proof: only enqueue_hot_load
        # sets it after stop_upload, and enqueue_hot_load only runs if the
        # TracePoint fired. extract_all cannot have been called because the
        # scheduler thread cannot fire without @scheduled_at set.
        eval('class SymdbStopUploadSpecPostStopClass; def hello; end; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
        expect(component.instance_variable_get(:@scheduled_at)).to be_nil
        expect(extraction_count).to eq(1)
      ensure
        Object.send(:remove_const, :SymdbStopUploadSpecPostStopClass) if Object.const_defined?(:SymdbStopUploadSpecPostStopClass)
      end
    end

    it 'enqueue_hot_load called after stop_upload does not re-arm the scheduler' do
      # Models the race where a :class TracePoint event fires concurrently
      # with stop_upload: TracePoint#disable does not wait for in-flight
      # callbacks, so the callback can reach enqueue_hot_load after the hook
      # has been torn down. Without the @hot_load_tracepoint guard,
      # enqueue_hot_load would re-arm the scheduler in this state.
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])
      component.start_upload
      component.wait_for_idle(timeout: 5)
      component.stop_upload

      component.send(:enqueue_hot_load, Object)

      expect(component.instance_variable_get(:@scheduled_at)).to be_nil
    end
  end

  describe 'config removal (ported from Java SymDBEnablementTest.removeSymDBConfig)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    it 'shutdown prevents any future uploads' do
      allow(component).to receive(:extract_and_upload)

      component.start_upload
      component.shutdown!

      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
      # start_upload enters the scheduler mutex, sees @shutdown=true, and returns.
      # No new scheduler thread is started; shutdown! already joined the previous one.
      expect(component.instance_variable_get(:@scheduler_thread)).to be_nil
    end
  end

  describe 'filtering behavior (ported from Java SymDBEnablementTest.noIncludesFilterOutDatadogClass)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'extract_and_upload filters out Datadog internal classes' do
      uploaded_scopes = []
      mock_scope_batcher = instance_double(Datadog::SymbolDatabase::ScopeBatcher)
      allow(mock_scope_batcher).to receive(:add_scope) { |scope| uploaded_scopes << scope }
      allow(mock_scope_batcher).to receive(:flush)
      allow(mock_scope_batcher).to receive(:shutdown)
      component.instance_variable_set(:@scope_batcher, mock_scope_batcher)

      component.send(:extract_and_upload)

      datadog_scopes = uploaded_scopes.select { |s| s.name&.start_with?('Datadog::') }
      expect(datadog_scopes).to be_empty
    end
  end
end
