require "datadog/di/spec_helper"
require "datadog/di/component"

RSpec.describe Datadog::DI::Component do
  di_test

  describe ".build" do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.internal.development = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    let(:logger) do
      instance_double(Logger)
    end

    context "when remote config is enabled" do
      before do
        settings.remote.enabled = true
      end

      it "returns a Component in stopped state" do
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be_a(described_class)
        expect(component.started?).to be false
        component.shutdown!
      end
    end

    # Log level on build-time precondition failures follows the customer's
    # explicit intent: warn when DD_DYNAMIC_INSTRUMENTATION_ENABLED=true is
    # set, otherwise debug. Implicit-enabled customers receive their warn
    # from Remote.handle_rc_enablement when the RC signal lands on a nil
    # component.
    context "when remote config is disabled" do
      before do
        settings.remote.enabled = false
      end

      context "with DD_DYNAMIC_INSTRUMENTATION_ENABLED explicitly true" do
        before { settings.dynamic_instrumentation.enabled = true }

        it "returns nil and warns with the docs URL" do
          expect(logger).to receive(:warn).with(
            a_string_matching(%r{Remote Configuration is not enabled.*docs\.datadoghq\.com/agent/remote_config}),
          )
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end

      context "without DD_DYNAMIC_INSTRUMENTATION_ENABLED set" do
        it "returns nil and logs the RC-disabled reason at debug" do
          expect(logger).to receive(:debug).with(
            a_string_matching(%r{Remote Configuration is not enabled.*docs\.datadoghq\.com/agent/remote_config}),
          )
          expect(logger).not_to receive(:warn)
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end
    end

    context "when the runtime is unsupported (MRI required, mocked)" do
      before do
        settings.remote.enabled = true
        stub_const("RUBY_ENGINE", "jruby")
      end

      context "with DD_DYNAMIC_INSTRUMENTATION_ENABLED explicitly true" do
        before { settings.dynamic_instrumentation.enabled = true }

        it "returns nil and warns naming the engine" do
          expect(logger).to receive(:warn).with(a_string_matching(/MRI is required.*jruby/))
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end

      context "without DD_DYNAMIC_INSTRUMENTATION_ENABLED set" do
        it "returns nil and logs the MRI-required reason at debug" do
          expect(logger).to receive(:debug).with(a_string_matching(/MRI is required.*jruby/))
          expect(logger).not_to receive(:warn)
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end
    end

    context "when the runtime is unsupported (Ruby 2.6+ required, mocked)" do
      # Stub both RUBY_VERSION (used in the error message interpolation)
      # and Datadog::RubyVersion::CURRENT_RUBY_VERSION (the cached value
      # RubyVersion.is? compares against, captured at module load time).
      before do
        settings.remote.enabled = true
        stub_const("RUBY_VERSION", "2.5.0")
        stub_const("Datadog::RubyVersion::CURRENT_RUBY_VERSION", Gem::Version.new("2.5.0"))
      end

      context "with DD_DYNAMIC_INSTRUMENTATION_ENABLED explicitly true" do
        before { settings.dynamic_instrumentation.enabled = true }

        it "returns nil and warns naming the version" do
          expect(logger).to receive(:warn).with(a_string_matching(/Ruby 2\.6\+ is required.*2\.5\.0/))
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end

      context "without DD_DYNAMIC_INSTRUMENTATION_ENABLED set" do
        it "returns nil and logs the Ruby-version reason at debug" do
          expect(logger).to receive(:debug).with(a_string_matching(/Ruby 2\.6\+ is required.*2\.5\.0/))
          expect(logger).not_to receive(:warn)
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end
    end

    context "when C extension is not available" do
      before do
        settings.remote.enabled = true
        allow(Datadog::DI).to receive(:respond_to?).and_call_original
        allow(Datadog::DI).to receive(:respond_to?).with(:exception_message).and_return(false)
      end

      context "with DD_DYNAMIC_INSTRUMENTATION_ENABLED explicitly true" do
        before { settings.dynamic_instrumentation.enabled = true }

        it "returns nil and warns" do
          expect(logger).to receive(:warn).with(/C extension is not available/)
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end

      context "without DD_DYNAMIC_INSTRUMENTATION_ENABLED set" do
        it "returns nil and logs the C-extension-absent reason at debug" do
          expect(logger).to receive(:debug).with(a_string_matching(/C extension is not available/))
          expect(logger).not_to receive(:warn)
          expect(described_class.build(settings, agent_settings, logger)).to be nil
        end
      end
    end

    context "when DD_DYNAMIC_INSTRUMENTATION_ENABLED is explicitly false" do
      before do
        settings.remote.enabled = true
        settings.dynamic_instrumentation.enabled = false
      end

      it "returns nil and logs at debug without building a component" do
        expect(logger).to receive(:debug).with(
          a_string_matching(/explicitly disabled.*DD_DYNAMIC_INSTRUMENTATION_ENABLED=false/),
        )
        expect(logger).not_to receive(:warn)
        expect(described_class.build(settings, agent_settings, logger)).to be nil
      end
    end
  end

  describe ".explicitly_enabled?" do
    let(:settings) { Datadog::Core::Configuration::Settings.new }
    let(:di_settings) { settings.dynamic_instrumentation }

    context "when DD_DYNAMIC_INSTRUMENTATION_ENABLED is unset (default precedence)" do
      before { di_settings.enabled }

      it "returns false" do
        expect(described_class.explicitly_enabled?(settings)).to be false
      end
    end

    context "when DD_DYNAMIC_INSTRUMENTATION_ENABLED is explicitly set to true" do
      before { di_settings.enabled = true }

      it "returns true" do
        expect(described_class.explicitly_enabled?(settings)).to be true
      end
    end

    context "when DD_DYNAMIC_INSTRUMENTATION_ENABLED is explicitly set to false" do
      before { di_settings.enabled = false }

      it "returns false" do
        expect(described_class.explicitly_enabled?(settings)).to be false
      end
    end
  end

  describe "DI.add_current_component invariant from build" do
    # Guards the "two storage places" decision: built components are
    # tracked in BOTH Components#@dynamic_instrumentation
    # AND DI.@current_components, so the code-tracker callback (which has
    # no reference to Components) can locate the live component via
    # DI.current_component without round-tripping through Datadog.send(:components).
    # A future refactor that drops one of the two stores would be caught here.

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.remote.enabled = true
        s.dynamic_instrumentation.internal.development = true
      end
    end

    let(:agent_settings) { instance_double_agent_settings_with_stubs }
    let(:logger) { instance_double(Logger) }

    it "registers the built component in DI.current_component" do
      component = described_class.build(settings, agent_settings, logger)
      expect(component).not_to be_nil
      expect(Datadog::DI.current_component).to be component
      component.shutdown!
    end

    it "removes the component from DI.current_component on shutdown!" do
      component = described_class.build(settings, agent_settings, logger)
      component.shutdown!
      expect(Datadog::DI.current_component).not_to be component
    end
  end

  describe "build does not block" do
    # Companion to the handle_rc_enablement non-blocking guarantee.
    # DI startup must not block requests:
    # Component.build is called during Components#initialize — any blocking
    # call here delays application boot and Rack request handling. The
    # build path should perform no I/O: no socket open, no thread join,
    # no remote fetch. The constructor's only background work is allocating
    # the probe notifier worker thread object (not starting it).
    #
    # The bound here is loose because we're catching pathological
    # regressions (seconds-of-blocking) rather than profiling. CI variance
    # under load doesn't generally exceed 1s for an allocation-only path.

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.remote.enabled = true
        s.dynamic_instrumentation.internal.development = true
      end
    end

    let(:agent_settings) { instance_double_agent_settings_with_stubs }
    let(:logger) { instance_double(Logger) }

    it "completes synchronously without I/O" do
      baseline = Thread.list.size
      started = Datadog::Core::Utils::Time.get_time
      component = described_class.build(settings, agent_settings, logger)
      elapsed = Datadog::Core::Utils::Time.get_time - started
      expect(component).not_to be_nil
      expect(elapsed).to be < 1.0
      # build must not have spawned the probe notifier worker thread or
      # any other background thread — those start in #start!.
      expect(Thread.list.size).to eq baseline
      component.shutdown!
    end
  end

  describe "#start! and #stop!" do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.internal.development = true
      settings.remote.enabled = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    let(:logger) do
      instance_double(Logger)
    end

    let(:component) do
      described_class.build(settings, agent_settings, logger)
    end

    after do
      component&.shutdown!
    end

    it "starts and stops the component" do
      expect(component.started?).to be false
      component.start!
      expect(component.started?).to be true
      component.stop!
      expect(component.started?).to be false
    end

    it "start! is idempotent" do
      component.start!
      component.start!
      expect(component.started?).to be true
    end

    it "stop! is idempotent" do
      component.stop!
      component.stop!
      expect(component.started?).to be false
    end

    it "supports restart after stop" do
      component.start!
      expect(component.started?).to be true
      component.stop!
      expect(component.started?).to be false
      component.start!
      expect(component.started?).to be true
    end

    context "when code tracking is activated after the component is built (in-product enablement)" do
      before do
        # Simulate DI disabled at boot: no global code tracker exists when the
        # component (and its instrumenter) are built. Stop any tracker a prior
        # example left active before dropping the global reference: nilling
        # @code_tracker while its process-global :script_compiled TracePoint is
        # still enabled orphans the TracePoint (deactivate_tracking! can no longer
        # reach it), leaking it into later specs and double-firing
        # code_tracker_spec's line-probe-installation examples.
        Datadog::DI.deactivate_tracking!
        Datadog::DI.instance_variable_set(:@code_tracker, nil)
      end

      after do
        Datadog::DI.deactivate_tracking!
        Datadog::DI.instance_variable_set(:@code_tracker, nil)
      end

      it "adopts the global code tracker on start!" do
        expect(component.instrumenter.code_tracker).to be_nil

        Datadog::DI.activate_tracking!
        expect(Datadog::DI.code_tracker).not_to be_nil

        component.start!

        expect(component.instrumenter.code_tracker).to be(Datadog::DI.code_tracker)
        expect(component.code_tracker).to be(Datadog::DI.code_tracker)
      end
    end

    it "spawns a background thread on start! and reaps it on stop!" do
      baseline = Thread.list.size
      expect(component.started?).to be false
      # Component built but not yet started — no new threads beyond baseline.
      expect(Thread.list.size).to eq(baseline)

      component.start!
      expect(Thread.list.size).to be > baseline

      # ProbeNotifierWorker#stop calls thread.join (or thread.kill on timeout),
      # so by the time component.stop! returns the worker thread is gone.
      component.stop!
      expect(Thread.list.size).to eq(baseline)
    end

    it "definition trace point is disabled when stopped" do
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be false
    end

    it "definition trace point is enabled after start" do
      component.start!
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be true
    end

    it "definition trace point is disabled after stop" do
      component.start!
      component.stop!
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be false
    end

    it "definition trace point is re-enabled after restart" do
      component.start!
      component.stop!
      component.start!
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be true
    end
  end

  describe "@lifecycle_mutex serialization" do
    # The mutex serializes start!, stop!, and shutdown! so concurrent RC
    # callbacks (which run on the remote-config worker thread) cannot race
    # a foreground operation.
    #
    # The behavioral guarantee — "two threads calling start!/stop!
    # concurrently are serialized" — is provided by Ruby's Mutex#synchronize.
    # We do not re-test Ruby's mutex here. What we test is the mechanism:
    # each lifecycle method must wrap its body in @lifecycle_mutex.synchronize,
    # so that Ruby's guarantee actually applies.
    #
    # Without the mutex (or with a refactor that accidentally drops it from
    # one method), a stop! called during start!'s critical section would
    # observe @started == false, short-circuit on `return unless @started`,
    # and silently no-op — losing the customer's stop! intent.

    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.internal.development = true
      settings.remote.enabled = true
      settings
    end

    let(:agent_settings) { instance_double_agent_settings_with_stubs }
    let(:logger) { instance_double(Logger) }
    let(:component) { described_class.build(settings, agent_settings, logger) }
    let(:mutex) { component.instance_variable_get(:@lifecycle_mutex) }

    before do
      # Stub the lifecycle method bodies so the test asserts only on the
      # mutex acquisition, not on the worker/probe-manager side effects
      # (already covered by the #start! and #stop! describe above).
      allow(component.probe_notifier_worker).to receive(:start)
      allow(component.probe_notifier_worker).to receive(:stop)
      allow(component.probe_manager).to receive(:reopen)
      allow(component.probe_manager).to receive(:stop)
      allow(component.probe_manager).to receive(:clear_hooks)
      allow(component.probe_manager).to receive(:close)
    end

    # Targeted cleanup: remove the component from DI.current_components without
    # going through shutdown!, because shutdown! itself acquires @lifecycle_mutex
    # and would be counted against the mock expectations below. The before block
    # stubs all worker/probe_manager side effects, so no thread/hook needs
    # stopping — the only state that escapes the example is the entry that
    # Component.build added to DI.current_components via add_current_component.
    after { Datadog::DI.remove_current_component(component) if component }

    it "start! acquires @lifecycle_mutex" do
      expect(mutex).to receive(:synchronize).and_call_original
      component.start!
    end

    it "stop! acquires @lifecycle_mutex" do
      component.start!
      expect(mutex).to receive(:synchronize).and_call_original
      component.stop!
    end

    it "shutdown! acquires @lifecycle_mutex" do
      expect(mutex).to receive(:synchronize).and_call_original
      component.shutdown!
    end
  end

  describe "#parse_probe_spec_and_notify" do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.remote.enabled = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    let(:logger) do
      instance_double(Logger)
    end

    let(:telemetry) do
      instance_double(Datadog::Core::Telemetry::Component)
    end

    let(:component) do
      described_class.build(settings, agent_settings, logger, telemetry: telemetry).tap(&:start!)
    end

    let(:probe_spec) do
      {
        "id" => "test-probe-id",
        "type" => "LOG_PROBE",
      }
    end

    after do
      component&.shutdown!
    end

    context "when building error notification fails" do
      it "reports exception to telemetry" do
        allow(logger).to receive(:debug)

        # Make ProbeBuilder raise an error
        expect(Datadog::DI::ProbeBuilder).to receive(:build_from_remote_config).and_raise(StandardError, "probe build error")

        # Make the error notification building also fail
        expect(component.probe_notification_builder).to receive(:build_errored).and_raise(RuntimeError, "notification build error")

        expect(telemetry).to receive(:report) do |exc, description:|
          expect(exc).to be_a(RuntimeError)
          expect(exc.message).to eq("notification build error")
          expect(description).to eq("Error building probe error notification")
        end

        expect do
          component.parse_probe_spec_and_notify(probe_spec)
        end.to raise_error(RuntimeError, "notification build error")
      end
    end
  end
end
