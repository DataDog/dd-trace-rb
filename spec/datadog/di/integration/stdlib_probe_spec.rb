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
# Key finding: for capture probes (rate limit 1/sec), the rate limiter
# prevents infinite recursion because nested invocations are rate-limited
# and just call the original method via super.
# For non-capture probes (rate limit 5000/sec), the higher rate limit
# allows many nested invocations, which can cause SystemStackError
# (see String#length without snapshot capture test).
#
# Another subtlety: stdlib methods like Hash#each are called by DI's
# own code during probe installation and diagnostics. The first call
# after installation consumes the rate limiter token, so test mocks
# must be set up BEFORE probe installation to observe this.

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
