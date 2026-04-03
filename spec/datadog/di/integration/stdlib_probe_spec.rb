require "datadog/di/spec_helper"
require "datadog/di"
require "set"

# Integration tests that set DI probes on standard library methods
# invoked by DI's own processing pipeline.
#
# DI has no explicit re-entrancy guards. When a probe is set on a stdlib
# method that DI calls internally (e.g., String#length in the serializer),
# the probe fires during DI's own processing, creating a re-entrant
# invocation. These tests verify that DI handles this gracefully
# (via rate limiting, serialization depth limits, or error recovery)
# and document cases where it does not.
#
# Key findings:
#
# 1. Line probes (TracePoint) are NOT vulnerable to re-entrancy.
#    Ruby self-disables a TracePoint during its callback, preventing
#    the same trace point from firing while already processing.
#
# 2. Method probes (module prepending) ARE vulnerable.
#    Module prepending has no re-entrancy protection. The vulnerability
#    manifests when:
#    a) The probed method is called in the always-executed snapshot
#       building path (e.g., String#length via SecureRandom.uuid), AND
#    b) The rate limit is high enough to allow nested invocations
#       (5000/sec for non-capture probes).
#    Capture probes (1/sec rate limit) are safe because the rate limiter
#    blocks nested invocations.
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
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
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

      it "causes SystemStackError due to re-entrancy without capture rate limit protection" do
        # Without snapshot capture, rate limit is 5000/sec.
        # The recursion path is:
        #   String#length probe fires ->
        #   DI builds snapshot (no capture) ->
        #   SecureRandom.uuid calls gen_random_urandom ->
        #   gen_random_urandom calls String#length ->
        #   String#length probe fires again ->
        #   ... infinite recursion
        #
        # The rate limiter (5000/sec) cannot prevent this because the
        # recursion happens faster than the rate limit check can stop it.
        # The SystemStackError occurs inside rate_limiter.allow? itself.
        #
        # This demonstrates that DI needs re-entrancy guards (e.g.,
        # a thread-local flag) to safely handle probes on hot stdlib methods
        # with high rate limits.
        expect do
          run_stdlib_probe_test(probe) do
            StdlibProbeTestClass.new.call_string_length("hello world")
          end
        end.to raise_error(SystemStackError)
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
  # Line probe on Ruby-implemented stdlib file (set.rb)
  # ----------------------------------------------------------------

  context "line probe on Set#include? (set.rb)" do
    # Set#include? is called by DI's redactor during serialization
    # (redactor.rb: `redacted_identifiers.include?(normalize(name))`).
    # set.rb is Ruby-implemented, so line probes can target it.
    # Since set.rb is loaded before code tracking starts, we must use
    # untargeted trace points.

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.remote.enabled = true
        settings.dynamic_instrumentation.enabled = true
        settings.dynamic_instrumentation.internal.development = true
        settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
        settings.dynamic_instrumentation.internal.untargeted_trace_points = true
      end
    end

    let(:set_source_file) do
      Set.instance_method(:include?).source_location&.first
    end

    let(:set_include_line) do
      # The body of Set#include? (the @hash[o] line, one after `def`)
      loc = Set.instance_method(:include?).source_location
      loc ? loc.last + 1 : nil
    end

    let(:probe) do
      skip "Cannot determine Set#include? source location" unless set_source_file && set_include_line

      Datadog::DI::Probe.new(
        id: "stdlib-set-include-line",
        type: :log,
        file: set_source_file,
        line_no: set_include_line,
        capture_snapshot: true,
      )
    end

    context "with snapshot capture" do
      it "installs line probe on stdlib and fires" do
        skip "Cannot determine Set#include? source location" unless set_source_file && set_include_line

        payloads = run_stdlib_probe_test(probe) do
          s = Set.new([:a, :b, :c])
          expect(s.include?(:b)).to be true
          expect(s.include?(:d)).to be false
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
        skip "Cannot determine Set#include? source location" unless set_source_file && set_include_line

        Datadog::DI::Probe.new(
          id: "stdlib-set-include-line-no-snap",
          type: :log,
          file: set_source_file,
          line_no: set_include_line,
          capture_snapshot: false,
        )
      end

      it "does not cause SystemStackError because TracePoint is self-disabling" do
        skip "Cannot determine Set#include? source location" unless set_source_file && set_include_line

        payloads = run_stdlib_probe_test(probe) do
          s = Set.new([:a, :b, :c])
          expect(s.include?(:b)).to be true
          expect(s.include?(:d)).to be false
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
    # The split re-entrancy guard (proposed in the investigation doc)
    # only prevents re-entrancy during an active probe callback. It does
    # NOT suppress probes during DI code paths that run outside of any
    # probe callback: add_probe, flush, shutdown, diagnostics.
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

    it "currently fires probe for DI-internal invocations during snapshot building" do
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

    it "installs without infinite recursion" do
      run_stdlib_probe_test(probe) do
        # The probe on Module#prepend fired during its own installation.
        # Trigger an additional prepend to verify the system is stable.
        mod = Module.new
        Class.new.prepend(mod)
      end

      # The key assertion is that we reach this point without
      # hanging or crashing. Payloads may or may not be generated
      # depending on rate limiting.
    end
  end
end
