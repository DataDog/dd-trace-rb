require "datadog/core/utils/base64_codec"

module DIHelpers
  class TestRemoteConfigGenerator
    def initialize(probe_configs)
      @probe_configs = probe_configs
    end

    attr_reader :probe_configs

    def insert_transaction(repository)
      repository.transaction do |_repository, transaction|
        probe_configs.each do |key, value|
          value_json = value.to_json

          target = Datadog::Core::Remote::Configuration::Target.parse(
            target_payload_for_value(value_json),
          )

          content = Datadog::Core::Remote::Configuration::Content.parse(
            {
              path: key,
              content: value_json,
            },
          )

          transaction.insert(content.path, target, content)
        end
      end
    end

    def mock_response
      RSpec::Mocks::Double.new(Datadog::Core::Remote::Transport::HTTP::Config::Response,
        ok?: true,
        empty?: false,
        roots: [],
        targets: targets,
        target_files: target_files,
        client_configs: client_configs)
    end

    private

    def target_payload_for_value(value)
      encoded = encode_obj(value)
      {
        "custom" => {
          "v" => 1,
        },
        "hashes" => {"sha256" => Digest::SHA256.hexdigest(encoded)},
        "length" => encoded.length,
      }
    end

    def client_configs
      probe_configs.keys.map do |k|
        rc_key_for_probe_id(k)
      end
    end

    def targets
      {
        "signed" => {
          "expires" => "2022-09-22T09:01:04Z",
          "targets" => probe_configs.map do |k, v|
            [rc_key_for_probe_id(k), target_payload_for_value(v)]
          end.to_h,
          "version" => 0,
          "custom" => {},
        },
      }
    end

    def rc_key_for_probe_id(id)
      # "datadog/2/LIVE_DEBUGGING/#{id}/hash"
      id
    end

    def target_files
      probe_configs.map do |k, v|
        {path: k, content: encode_obj(v)}
      end
    end

    def encode_str(v)
      Datadog::Core::Utils::Base64Codec.strict_encode64(v).chomp
    end

    def encode_obj(v)
      JSON.dump(v)
      # encode_str(JSON.dump(v))
    end
  end

  module ClassMethods
    def deactivate_code_tracking
      before(:all) do
        deactivate_code_tracking_if_supported
      end
    end

    def di_test
      if PlatformHelpers.jruby?
        before(:all) do
          skip "Dynamic instrumentation is not supported on JRuby"
        end
      end
      if RubyVersion.is?("< 2.6")
        before(:all) do
          skip "Dynamic instrumentation requires Ruby 2.6 or higher"
        end
      end

      let(:di_instrumented_count_at_start) { Datadog::DI.instrumented_count }

      prepend_before do
        if di_instrumented_count_at_start > 0
          # Leaking instrumentations is a serious problem, but we want the
          # diagnostics to point to the root cause. If there are outstanding
          # instrumentations at the start of the test, the value at the end
          # is likely to be meaningless. But just in case the report that
          # is attached to the "root cause" test somehow disappears, warn
          # that there are outstanding instrumentations here.
          # They just produce noise in logs but not meaningless test failures.
          warn "DI: #{Datadog::DI.instrumented_count} outstanding instrumentations detected before test: #{Datadog::DI.instrumented_count(:method)} method instrumentations active, #{Datadog::DI.instrumented_count(:line)} line instrumentations active"
        end
      end

      # Checked in an after hook: an exception raised by an around hook after
      # example.run skips the rest of every enclosing around hook, including
      # the global tracer_shutdown! hook.
      append_after do
        if di_instrumented_count_at_start == 0 && Datadog::DI.instrumented_count > 0
          raise "DI: #{Datadog::DI.instrumented_count} outstanding instrumentations detected after test: #{Datadog::DI.instrumented_count(:method)} method instrumentations active, #{Datadog::DI.instrumented_count(:line)} line instrumentations active"
        end
      end
    end

    def mock_settings_for_di(&block)
      let(:settings) do
        double("settings").tap do |settings|
          allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
          if block
            instance_exec(settings, &block)
          end
        end
      end

      let(:di_settings) do
        double("di settings").tap do |settings|
          # Default to a large evaluation budget so existing DI specs preserve
          # their pre-timeout behavior; specs exercising the cooperative bound
          # override this with a real value.
          allow(settings).to receive_messages(
            internal: di_internal_settings,
            redaction_excluded_identifiers: [],
            max_time_to_evaluate_ms: 1_000_000,
          )
        end
      end

      let(:di_internal_settings) do
        double("di internal settings")
      end
    end

    def with_code_tracking
      around do |example|
        Datadog::DI.activate_tracking!
        example.run
      ensure
        Datadog::DI.deactivate_tracking!
      end
    end

    def without_code_tracking
      before do
        Datadog::DI.deactivate_tracking!
      end
    end

    def di_logger_double
      let(:logger) do
        instance_double(Datadog::DI::Logger).tap do |logger|
          allow(logger).to receive(:trace)
        end
      end
    end

    # Deactivates code tracking after each example, for examples whose
    # Datadog.configure call starts DI, which activates code tracking for
    # the rest of the process.
    def deactivate_code_tracking_after_each
      after do
        deactivate_code_tracking_if_supported
      end
    end

    def load_yaml_file(path, **opts)
      if RubyVersion.is?("< 3.1")
        opts.delete(:permitted_classes)
      end
      YAML.load_file(path, **opts)
    end
  end

  module InstanceMethods
    # Deactivates code tracking on runtimes that load DI code tracking
    # (MRI 2.6+).
    def deactivate_code_tracking_if_supported
      Datadog::DI.deactivate_tracking! if Datadog::DI.respond_to?(:deactivate_tracking!)
    end

    # Builds a telemetry component double whose metric increments raise the
    # given exception, for exercising emission containment paths.
    def telemetry_double_raising_on_inc(exception: StandardError.new("telemetry down"))
      instance_double(Datadog::Core::Telemetry::Component).tap do |telemetry|
        allow(telemetry).to receive(:inc).and_raise(exception)
        allow(telemetry).to receive(:report)
      end
    end

    # Helper method to generate a deeply nested hash for circuit breaker tests
    def generate_deep_hash(keys_per_level, depth)
      return "leaf_value" if depth == 0

      hash = {}
      keys_per_level.times do |i|
        hash[:"key_#{i}"] = generate_deep_hash(keys_per_level, depth - 1)
      end
      hash
    end

    def order_hash_keys(hash)
      hash.keys.map do |key|
        [key.to_s, hash[key]]
      end.to_h
    end

    def deep_stringify_keys(hash)
      if Hash === hash
        hash.map do |key, value|
          [key.to_s, deep_stringify_keys(value)]
        end.to_h
      else
        hash
      end
    end

    # Stubs the dynamic instrumentation settings accessors read by the
    # serialization and evaluation paths, with per-spec overrides for the
    # values that differ.
    def stub_di_settings(settings, enabled: true, max_capture_depth: 2,
      max_capture_attribute_count: 2, max_capture_string_length: 100,
      max_capture_collection_size: 100, max_time_to_serialize_ms: 200,
      max_time_to_evaluate_ms: 1_000_000,
      redacted_type_names: [], redacted_identifiers: [], redaction_excluded_identifiers: [])
      allow(settings).to receive_messages(
        enabled: enabled,
        max_capture_depth: max_capture_depth,
        max_capture_attribute_count: max_capture_attribute_count,
        max_capture_string_length: max_capture_string_length,
        max_capture_collection_size: max_capture_collection_size,
        max_time_to_serialize_ms: max_time_to_serialize_ms,
        max_time_to_evaluate_ms: max_time_to_evaluate_ms,
        redacted_type_names: redacted_type_names,
        redacted_identifiers: redacted_identifiers,
        redaction_excluded_identifiers: redaction_excluded_identifiers,
      )
    end

    def instance_double_agent_settings
      instance_double(Datadog::Core::Configuration::AgentSettings)
    end

    def instance_double_agent_settings_with_stubs
      instance_double(
        Datadog::Core::Configuration::AgentSettings,
        hostname: "test-host", port: 9000, timeout_seconds: 1, ssl: false,
      )
    end

    # Stub the active APM trace that the correlation gate and the snapshot
    # builder read through the Datadog::DI seam, plus the active span the
    # builder reports.
    def stub_active_trace(trace_id, span_id: nil)
      trace = instance_double(Datadog::Tracing::TraceOperation, id: trace_id)
      allow(Datadog::DI).to receive(:active_trace).and_return(trace)
      if span_id
        span = instance_double(Datadog::Tracing::SpanOperation, id: span_id)
        allow(Datadog::DI).to receive(:active_span).and_return(span)
      end
    end

    # Stub the absence of an active APM trace.
    def stub_no_trace
      allow(Datadog::DI).to receive(:active_trace).and_return(nil)
      allow(Datadog::DI).to receive(:active_span).and_return(nil)
    end

    # Freeze the time provider the rate limiters refill from, so their
    # buckets hold a fixed balance for the rest of the example: the current
    # time is captured before the stub takes effect, so every refill adds
    # zero tokens.
    def freeze_rate_limiter_clock
      frozen_time = Datadog::Core::Utils::Time.get_time
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(frozen_time)
    end
  end
end

module ProbeNotifierWorkerLeakDetector
  class << self
    attr_accessor :installed
    attr_accessor :workers

    # Warns about each leaked worker, then stops tracking the reported
    # workers so that each leak is reported once.
    def verify!
      leaked_workers = workers
      self.workers = []
      leaked_workers.each do |(worker, example)|
        origin = example ? "in #{example.file_path}: #{example.full_description}" : "outside of an example"
        warn "Leaked #{worker} started #{origin}"
      end
    end
  end

  ProbeNotifierWorkerLeakDetector.workers = []

  def start
    unless ProbeNotifierWorkerLeakDetector.workers.any? { |(worker, _example)| worker.equal?(self) }
      ProbeNotifierWorkerLeakDetector.workers << [self, RSpec.current_example]
    end
    super
  end

  def stop(*args)
    ProbeNotifierWorkerLeakDetector.workers.delete_if do |(worker, _example)|
      worker == self
    end
    super
  end
end

RSpec.configure do |config|
  config.extend DIHelpers::ClassMethods
  config.include DIHelpers::InstanceMethods

  # DI does not do anything on Ruby < 2.6 therefore there is no need
  # to install a leak detector on lower Ruby versions.
  if RubyVersion.is?(">= 2.6")
    # Leaks are verified when the next example starts and when the suite
    # finishes, because around hooks and the global tracer_shutdown! hook
    # stop workers after every after hook has run.
    config.before do |example|
      if defined?(Datadog::DI::ProbeNotifierWorker) && !ProbeNotifierWorkerLeakDetector.installed
        Datadog::DI::ProbeNotifierWorker.send(:prepend, ProbeNotifierWorkerLeakDetector)
        ProbeNotifierWorkerLeakDetector.installed = true
      end

      # Forked examples run this hook in a child process whose updates to
      # the workers list never reach the parent, so verifying there only
      # duplicates the parent's eventual report.
      ProbeNotifierWorkerLeakDetector.verify! unless example.metadata[:execute_in_fork]
    end

    config.after(:suite) do
      ProbeNotifierWorkerLeakDetector.verify!
    end
  end
end
