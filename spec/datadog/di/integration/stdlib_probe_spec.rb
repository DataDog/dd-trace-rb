require "datadog/di/spec_helper"
require "datadog/di"
require "set"
require "securerandom"

# Integration tests that set DI probes on standard library methods
# invoked by DI's own processing pipeline.
#
# Method probes use a fiber-local re-entrancy guard accessed via
# Datadog::DI.in_probe? / .enter_probe / .leave_probe. Those methods are
# implemented in C and call rb_thread_local_aref / rb_thread_local_aset
# directly, bypassing Thread#[] / Thread#[]= method dispatch — so a user
# probe on those Thread methods cannot intercept guard reads/writes.
# The guard is a split design: held during DI pre/post-processing, released
# during super() so nested probes fire normally in user code. These tests
# verify the guard works correctly and document remaining edge cases.
#
# Key findings:
#
# 1. Line probes (TracePoint) are NOT vulnerable to re-entrancy.
#    Ruby self-disables a TracePoint during its callback, preventing
#    the same trace point from firing while already processing.
#
# 2. Method probes (module prepending) are protected by the split
#    re-entrancy guard. Without the guard, the vulnerability manifests
#    when:
#    a) The probed method is called in the always-executed snapshot
#       building path (e.g., String#length via SecureRandom.uuid), AND
#    b) The rate limit is high enough to allow nested invocations
#       (5000/sec for non-capture probes).
#    Capture probes (1/sec rate limit) are additionally safe because
#    the rate limiter blocks nested invocations.
#
# 3. Methods only called in the capture-only serialization path
#    (e.g., Set#include? via redactor) are safe for non-capture probes
#    because that path isn't executed.
#
# 4. Stdlib methods like Hash#each fire during DI's own probe
#    installation/diagnostics, consuming the rate limiter token before
#    user code runs. Test mocks must be set up BEFORE probe installation.

# Test class whose methods invoke stdlib methods.
# We set probes on the stdlib methods themselves, then invoke these
# methods to trigger the probes.
class StdlibProbeTestClass
  def initialize
    @name = "test_instance"
  end

  def call_string_length(str)
    str.length
  end

  def call_hash_each(hash)
    result = []
    hash.each { |k, v| result << [k, v] }
    result
  end

  def call_array_map(array)
    array.map { |x| x.to_s }
  end

  def call_instance_variables(obj)
    obj.instance_variables
  end
end

RSpec.describe "Stdlib probe integration: probes on methods invoked by DI processing" do
  di_test

  let(:diagnostics_transport) do
    instance_double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    instance_double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(input_transport).to receive(:send_input)
    allow(Datadog::DI).to receive(:current_component).and_return(component)
  end

  after do
    component.shutdown!
  end

  let(:agent_settings) do
    instance_double_agent_settings_with_stubs
  end

  let(:logger) { logger_allowing_debug }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
    end
  end

  let(:probe_manager) do
    component.probe_manager
  end

  # Helper: set up mock, add probe, invoke block, flush, return payloads.
  # Sets up the add_snapshot mock BEFORE add_probe so that snapshots
  # generated during probe installation (from hot stdlib methods that
  # fire immediately) are captured.
  def run_stdlib_probe_test(probe)
    payloads = []
    allow(component.probe_notifier_worker).to receive(:add_snapshot) do |payload|
      payloads << payload
    end

    expect(diagnostics_transport).to receive(:send_diagnostics)
    probe_manager.add_probe(probe)

    yield

    component.probe_notifier_worker.flush
    payloads
  end

  # ----------------------------------------------------------------
  # Method probes on stdlib classes used by DI serializer
  # ----------------------------------------------------------------

  shared_context "propagate_all_exceptions settings" do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.remote.enabled = true
        settings.dynamic_instrumentation.enabled = true
        settings.dynamic_instrumentation.internal.development = true
        settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
      end
    end
  end

  shared_context "permissive settings" do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.remote.enabled = true
        settings.dynamic_instrumentation.enabled = true
        settings.dynamic_instrumentation.internal.development = true
        settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
      end
    end
  end

  context "method probe on String#length" do
    # String#length is called by DI's serializer to check string truncation
    # (serializer.rb: `if value.length > max`).
    # A probe here causes re-entrancy: user code calls length -> probe fires ->
    # DI serializes snapshot -> serializer calls length on strings -> probe
    # fires again. Rate limiter (1/sec for capture probes) prevents infinite
    # recursion because nested invocations are rate-limited.

    context "with snapshot capture" do
      include_context "permissive settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-string-length",
          type: :log,
          type_name: "String",
          method_name: "length",
          capture_snapshot: true,
        )
      end

      it "handles re-entrancy via rate limiting" do
        payloads = run_stdlib_probe_test(probe) do
          result = StdlibProbeTestClass.new.call_string_length("hello world")
          expect(result).to eq(11)
        end

        expect(payloads.length).to be >= 1
      end
    end

    context "without snapshot capture" do
      include_context "permissive settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-string-length-no-snap",
          type: :log,
          type_name: "String",
          method_name: "length",
          capture_snapshot: false,
        )
      end

      it "handles re-entrancy via fiber-local guard" do
        # Without snapshot capture, rate limit is 5000/sec.
        # Without the re-entrancy guard this would cause SystemStackError:
        #   String#length probe fires ->
        #   DI builds snapshot (no capture) ->
        #   SecureRandom.uuid calls gen_random_urandom ->
        #   gen_random_urandom calls String#length ->
        #   String#length probe fires again -> ... infinite recursion
        #
        # The fiber-local guard (DI.in_probe? / .enter_probe / .leave_probe,
        # implemented in C) prevents this: DI-internal calls to String#length
        # see the guard is set and call the original method directly.
        payloads = run_stdlib_probe_test(probe) do
          result = StdlibProbeTestClass.new.call_string_length("hello world")
          expect(result).to eq(11)
        end

        expect(payloads.length).to be >= 1
      end
    end
  end

  context "method probe on Hash#each" do
    # Hash#each is called by DI's serializer to iterate hash entries
    # (serializer.rb: `value.each do |k, v|`).
    # Hash#each is also called by DI's own code during probe installation
    # and diagnostics, so the probe fires immediately after installation.

    context "with snapshot capture" do
      include_context "propagate_all_exceptions settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-hash-each",
          type: :log,
          type_name: "Hash",
          method_name: "each",
          capture_snapshot: true,
        )
      end

      it "handles re-entrancy via rate limiting" do
        payloads = run_stdlib_probe_test(probe) do
          result = StdlibProbeTestClass.new.call_hash_each({a: 1, b: 2})
          expect(result).to eq([[:a, 1], [:b, 2]])
        end

        expect(payloads.length).to be >= 1
      end
    end
  end

  context "method probe on Array#map" do
    # Array#map is called by DI's serializer to serialize array elements
    # (serializer.rb: `entries = value.map do |elt|`)
    # and by probe_notification_builder to format caller_locations.

    context "with snapshot capture" do
      include_context "permissive settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-array-map",
          type: :log,
          type_name: "Array",
          method_name: "map",
          capture_snapshot: true,
        )
      end

      it "handles re-entrancy via rate limiting" do
        payloads = run_stdlib_probe_test(probe) do
          result = StdlibProbeTestClass.new.call_array_map([1, 2, 3])
          expect(result).to eq(["1", "2", "3"])
        end

        expect(payloads.length).to be >= 1
      end
    end
  end

  context "method probe on Object#instance_variables" do
    # Object#instance_variables is called by DI's serializer to enumerate
    # fields of non-primitive objects
    # (serializer.rb: `ivars = value.instance_variables`).

    context "with snapshot capture" do
      include_context "permissive settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-obj-ivars",
          type: :log,
          type_name: "Object",
          method_name: "instance_variables",
          capture_snapshot: true,
        )
      end

      it "handles re-entrancy via rate limiting" do
        payloads = run_stdlib_probe_test(probe) do
          obj = StdlibProbeTestClass.new
          result = obj.call_instance_variables(obj)
          expect(result).to include(:@name)
        end

        expect(payloads.length).to be >= 1
      end
    end
  end

  # ----------------------------------------------------------------
  # Line probe on Ruby-implemented stdlib file (SecureRandom.uuid)
  # ----------------------------------------------------------------

  context "line probe on SecureRandom.uuid" do
    # SecureRandom.uuid is called by DI's probe notification builder
    # during every snapshot generation
    # (probe_notification_builder.rb: `id: SecureRandom.uuid`).
    #
    # The host file moves between Ruby versions: on 2.6/3.0 the method
    # is defined in lib/securerandom.rb; on 3.2+ it lives in
    # lib/random/formatter.rb and is extended into SecureRandom. The
    # test discovers the file dynamically via source_location, so the
    # move is invisible to the spec.
    #
    # Both files are Ruby-implemented across the supported Ruby
    # version range, so line probes can target them. Since they are
    # loaded before code tracking starts, we must use untargeted trace
    # points.

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.remote.enabled = true
        settings.dynamic_instrumentation.enabled = true
        settings.dynamic_instrumentation.internal.development = true
        settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
        settings.dynamic_instrumentation.internal.untargeted_trace_points = true
      end
    end

    let(:uuid_source_location) do
      loc = SecureRandom.method(:uuid).source_location
      unless loc
        raise "SecureRandom.uuid has no Ruby source location on Ruby " \
          "#{RUBY_VERSION} (likely reimplemented in C). This test verifies " \
          "line probes on a Ruby-implemented stdlib file called by DI's " \
          "snapshot pipeline; the target must be Ruby-implemented in the " \
          "current Ruby version. Either pick a different Ruby-implemented " \
          "target or replace this test."
      end
      loc
    end

    let(:source_file) { uuid_source_location.first }

    # First executable line of SecureRandom.uuid, one after `def`
    let(:source_line) { uuid_source_location.last + 1 }

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-securerandom-uuid-line",
        type: :log,
        file: source_file,
        line_no: source_line,
        capture_snapshot: true,
      )
    end

    context "with snapshot capture" do
      it "installs line probe on stdlib and fires" do
        payloads = run_stdlib_probe_test(probe) do
          SecureRandom.uuid
          SecureRandom.uuid
        end

        expect(payloads.length).to be >= 1
      end
    end

    context "without snapshot capture" do
      # Line probes use TracePoint, which Ruby self-disables during its
      # callback — the same trace point will NOT fire while already
      # inside its own callback. This is fundamentally different from
      # method probes (module prepending), which have no such protection.
      #
      # Therefore, non-capture line probes on stdlib methods should NOT
      # cause SystemStackError, unlike the equivalent method probe test
      # (String#length without capture).

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-securerandom-uuid-line-no-snap",
          type: :log,
          file: source_file,
          line_no: source_line,
          capture_snapshot: false,
        )
      end

      it "does not cause SystemStackError because TracePoint is self-disabling" do
        payloads = run_stdlib_probe_test(probe) do
          SecureRandom.uuid
          SecureRandom.uuid
        end

        # Unlike the method probe on String#length (no capture) which
        # causes SystemStackError, this line probe completes normally
        # because Ruby's TracePoint prevents re-entrant callback firing.
        expect(payloads.length).to be >= 1
      end
    end
  end

  # ----------------------------------------------------------------
  # Method probe on Set#include? — contrast with line probe above
  # ----------------------------------------------------------------

  context "method probe on Set#include?" do
    # Set#include? is called by DI's redactor during serialization.
    # Unlike the line probe test above (which uses TracePoint and is
    # self-disabling), this method probe uses module prepending and
    # has no re-entrancy protection.

    context "with snapshot capture" do
      include_context "permissive settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-set-include-method",
          type: :log,
          type_name: "Set",
          method_name: "include?",
          capture_snapshot: true,
        )
      end

      it "handles re-entrancy via rate limiting" do
        payloads = run_stdlib_probe_test(probe) do
          s = Set.new([:a, :b, :c])
          expect(s.include?(:b)).to be true
          expect(s.include?(:d)).to be false
        end

        expect(payloads.length).to be >= 1
      end
    end

    context "without snapshot capture" do
      include_context "permissive settings"

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "stdlib-set-include-method-no-snap",
          type: :log,
          type_name: "Set",
          method_name: "include?",
          capture_snapshot: false,
        )
      end

      it "does not cause SystemStackError because non-capture path does not call redactor" do
        # Without snapshot capture, DI's snapshot building does NOT call
        # the serializer or redactor. Set#include? is only called by
        # the redactor during capture serialization, so there is no
        # re-entrant invocation in the non-capture path.
        #
        # This contrasts with String#length (no capture) which DOES
        # cause SystemStackError because SecureRandom.uuid (called in
        # every snapshot) invokes String#length via gen_random_urandom.
        #
        # Vulnerability requires the probed method to be called in the
        # always-executed snapshot building path, not just in the
        # capture-only serialization path.
        payloads = run_stdlib_probe_test(probe) do
          s = Set.new([:a, :b, :c])
          expect(s.include?(:b)).to be true
        end

        expect(payloads.length).to be >= 1
      end
    end
  end

  # ----------------------------------------------------------------
  # DI-internal code should not fire probes
  # ----------------------------------------------------------------

  context "desired: probe on stdlib fires only for customer code, not DI-internal code" do
    # When a customer sets a probe on a stdlib method (e.g., String#length),
    # the desired behavior is:
    #   - DI-internal calls to String#length (during add_probe, serialization,
    #     snapshot building, flush, shutdown) should NOT fire the probe.
    #   - Only customer code calls to String#length should fire the probe.
    #
    # Currently DI has no mechanism to distinguish DI-internal calls from
    # customer code calls. The probe fires for ALL invocations, including
    # DI-internal ones. This has two consequences:
    #
    # 1. DI-internal invocations consume rate limiter tokens, potentially
    #    starving customer code of snapshots.
    # 2. DI-internal invocations can cause re-entrant recursion
    #    (SystemStackError for non-capture probes on hot methods).
    #
    # The split re-entrancy guard (in instrumenter.rb) only prevents
    # re-entrancy during an active probe callback. It does NOT suppress
    # probes during DI code paths that run outside of any probe
    # callback: add_probe, flush, shutdown, diagnostics.
    #
    # To fully suppress probes during all DI processing, the guard would
    # need to be set around every DI entry point.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-string-length-di-internal",
        type: :log,
        type_name: "String",
        method_name: "length",
        capture_snapshot: true,
      )
    end

    it "fires probe for both user code and DI-internal invocations (current behavior)" do
      payloads = run_stdlib_probe_test(probe) do
        # This single user-code call to String#length triggers the probe.
        # During DI's snapshot building for this invocation, DI calls
        # String#length internally (e.g., in serializer for truncation
        # checks, in SecureRandom.uuid). Those DI-internal calls ALSO
        # go through the probe wrapper — they are rate-limited (1/sec)
        # so they just call super, but they still consume overhead
        # checking the rate limiter and probe.enabled?.
        #
        # Desired: DI-internal calls should be completely invisible to
        # the probe — no rate limiter check, no enabled? check, just
        # the original method.
        StdlibProbeTestClass.new.call_string_length("hello world")
      end

      expect(payloads.length).to be >= 1
    end
  end

  # ----------------------------------------------------------------
  # Method probe on method called during probe installation
  # ----------------------------------------------------------------

  context "method probe on Module#prepend" do
    # Module#prepend is called by DI's instrumenter to install method probes
    # (instrumenter.rb: `cls.send(:prepend, mod)`).
    # A probe on prepend fires during probe installation itself.
    # This tests that DI can install a probe on a method it uses for
    # installation without entering infinite recursion.
    #
    # DI installs the probe by: 1) creating a module with define_method,
    # 2) calling cls.send(:prepend, mod). Step 2 triggers the probe on
    # Module#prepend, but the probe's own module was JUST prepended in
    # the same call, so the probe fires correctly (Module#prepend is
    # already instrumented by the time it fires).

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-module-prepend",
        type: :log,
        type_name: "Module",
        method_name: "prepend",
        capture_snapshot: true,
      )
    end

    it "installs without infinite recursion and the system is stable" do
      run_stdlib_probe_test(probe) do
        # The probe on Module#prepend fired during its own installation.
        # Trigger an additional prepend to verify the system is stable.
        mod = Module.new
        Class.new.prepend(mod)
      end

      # Probe is installed and the wrapper module is recorded on the probe.
      # Payloads may or may not be generated depending on rate limiting,
      # so the assertion is on installation state rather than payload count.
      expect(probe.instrumentation_module).to be_a(Module)
    end
  end

  context "method probe on Thread#[]" do
    # The re-entrancy guard storage is the same fiber-local hashtable that
    # Thread#[] / Thread#[]= read and write. A naive implementation that
    # accessed the storage via Thread#[] from Ruby would self-recurse here:
    #   user calls Thread#[] -> probe wrapper fires -> guard check calls
    #   Thread#[] -> probe wrapper fires -> ... SystemStackError.
    #
    # DI.in_probe? (and enter_probe / leave_probe) are implemented in C
    # using rb_thread_local_aref / rb_thread_local_aset, which read/write
    # the same hashtable directly without going through Thread#[] method
    # dispatch. The probe wrapper's own guard accesses are therefore
    # invisible to the user-installed Thread#[] probe.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-thread-aref",
        type: :log,
        type_name: "Thread",
        method_name: "[]",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through guard storage" do
      payloads = run_stdlib_probe_test(probe) do
        Thread.current[:user_key] = 42
        expect(Thread.current[:user_key]).to eq(42)
      end

      expect(payloads.length).to be >= 1
    end
  end

  context "method probe on Thread#[]=" do
    # Same reasoning as Thread#[]: writes to the guard storage from Ruby
    # via Thread#[]= would self-recurse. DI.enter_probe / DI.leave_probe
    # bypass Thread#[]= via rb_thread_local_aset.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-thread-aset",
        type: :log,
        type_name: "Thread",
        method_name: "[]=",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through guard storage" do
      payloads = run_stdlib_probe_test(probe) do
        Thread.current[:user_key] = 42
        expect(Thread.current[:user_key]).to eq(42)
      end

      expect(payloads.length).to be >= 1
    end
  end

  context "method probe on Array#empty?" do
    # The method probe wrapper tests args shape via DI.array_empty?(args),
    # implemented in C and called as a singleton method on Datadog::DI.
    # A naive implementation that called args.empty? from Ruby would
    # self-recurse here: a probe on Array#empty? would intercept the
    # wrapper's own emptiness check and re-enter the wrapper indefinitely.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-array-empty",
        type: :log,
        type_name: "Array",
        method_name: "empty?",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through wrapper emptiness check" do
      payloads = run_stdlib_probe_test(probe) do
        expect([].empty?).to be true
        expect([1].empty?).to be false
      end

      expect(payloads.length).to be >= 1
    end
  end

  context "method probe on Hash#empty?" do
    # Same reasoning as Array#empty?: the wrapper tests kwargs shape via
    # DI.hash_empty?(kwargs), implemented in C. A probe on Hash#empty?
    # cannot intercept that check, so no recursion.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-hash-empty",
        type: :log,
        type_name: "Hash",
        method_name: "empty?",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through wrapper emptiness check" do
      payloads = run_stdlib_probe_test(probe) do
        expect({}.empty?).to be true
        expect({a: 1}.empty?).to be false
      end

      expect(payloads.length).to be >= 1
    end
  end

  context "method probe on Proc#call" do
    # The wrapper used to invoke `do_super` via `do_super.call(args, kwargs, blk)`.
    # `do_super` is a lambda (Proc), so `.call` dispatches through Proc#call.
    # With Proc#call probed, that dispatch is intercepted by the wrapper.
    # The early-return at the top of the wrapper would itself call
    # `do_super.call`, so even with the guard set, recursion through Proc#call
    # could not terminate — every wrapper invocation creates a fresh do_super
    # lambda and re-enters Proc#call until SystemStackError.
    #
    # Fix: DI.invoke_proc(proc, *args), implemented in C via
    # rb_proc_call_with_block, invokes the Proc directly without going through
    # Proc#call dispatch. All do_super.call sites and user_caller_locations.call
    # in the wrapper / run_method_probe use DI.invoke_proc.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-proc-call",
        type: :log,
        type_name: "Proc",
        method_name: "call",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through wrapper trampoline" do
      payloads = run_stdlib_probe_test(probe) do
        adder = ->(a, b) { a + b }
        expect(adder.call(2, 3)).to eq(5)
      end

      expect(payloads.length).to be >= 1
    end
  end

  context "method probe on Object#send" do
    # The wrapper used to call `instrumenter.send(:run_method_probe, ...)`
    # because run_method_probe was private. With Object#send probed, that .send
    # would be intercepted by the wrapper before DI.enter_probe ran (the guard
    # was set inside run_method_probe), so DI.in_probe? was false on the
    # recursive entry and the wrapper recursed indefinitely.
    #
    # Fix: run_method_probe is now public; the wrapper calls it directly. No
    # `.send` on the hot path means an Object#send / Kernel#send probe cannot
    # intercept the call into run_method_probe.

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-object-send",
        type: :log,
        type_name: "Object",
        method_name: "send",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through wrapper send call" do
      payloads = run_stdlib_probe_test(probe) do
        target = Object.new
        def target.greet(name)
          "hello, #{name}"
        end
        expect(target.send(:greet, "world")).to eq("hello, world")
      end

      expect(payloads.length).to be >= 1
    end
  end

  context "method probe on Kernel#lambda" do
    # The wrapper used to construct do_super via `lambda do |a, k, blk| ... end`,
    # which dispatches through Kernel#lambda (method call, not syntax). With
    # Kernel#lambda probed, that dispatch was intercepted by the wrapper itself,
    # which again tried to construct do_super via lambda, recursing until
    # SystemStackError. The guard set inside run_method_probe was reached only
    # after do_super construction, so the early-return at the top of the wrapper
    # could not break the cycle.
    #
    # Fix: lambda literal `->(a, k, blk) { ... }` is syntax — no method dispatch —
    # so a probe on Kernel#lambda cannot intercept do_super construction. The same
    # `->` form is already used on the user_caller_locations site in the wrapper.
    #
    # Skip on Ruby < 3.0: prepending a `lambda` method onto Kernel does not
    # intercept `lambda { ... }` calls on Ruby 2.7 — empirically the wrapper
    # is never entered, so the recursion bug being tested is not reachable
    # there. The fix is only relevant on Ruby versions where the prepend
    # intercepts (verified on 3.2+).

    include_context "permissive settings"

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "stdlib-kernel-lambda",
        type: :log,
        type_name: "Kernel",
        method_name: "lambda",
        capture_snapshot: false,
      )
    end

    it "does not self-recurse through wrapper trampoline construction" do
      skip "Kernel#lambda prepend interception requires Ruby 3.0+" if RUBY_VERSION < "3.0"

      payloads = run_stdlib_probe_test(probe) do
        f = lambda { |x| x * 2 }
        expect(f.call(3)).to eq(6)
      end

      expect(payloads.length).to be >= 1
    end
  end
end
