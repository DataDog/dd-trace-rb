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
            target_payload_for_value(value_json)
          )

          content = Datadog::Core::Remote::Configuration::Content.parse(
            {
              path: key,
              content: value_json,
            }
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
        client_configs: client_configs,)
    end

    private

    def target_payload_for_value(value)
      encoded = encode_obj(value)
      {
        'custom' => {
          'v' => 1,
        },
        'hashes' => {'sha256' => Digest::SHA256.hexdigest(encoded)},
        'length' => encoded.length
      }
    end

    def client_configs
      probe_configs.keys.map do |k|
        rc_key_for_probe_id(k)
      end
    end

    def targets
      {
        'signed' => {
          'expires' => '2022-09-22T09:01:04Z',
          'targets' => probe_configs.map do |k, v|
            [rc_key_for_probe_id(k), target_payload_for_value(v)]
          end.to_h,
          'version' => 0,
          'custom' => {},
        },
      }
    end

    def rc_key_for_probe_id(id)
      #"datadog/2/LIVE_DEBUGGING/#{id}/hash"
      id
    end

    def target_files
      probe_configs.map do |k, v|
        {path: k, content: encode_obj(v)}
      end
    end

    def encode_str(v)
      Datadog::Core::Utils::Base64.strict_encode64(v).chomp
    end

    def encode_obj(v)
      JSON.dump(v)
      #encode_str(JSON.dump(v))
    end
  end

  module ClassMethods
    def deactivate_code_tracking
      before(:all) do
        if Datadog::DI.respond_to?(:deactivate_tracking!)
          Datadog::DI.deactivate_tracking!
        end
      end
    end

    def di_test
      if PlatformHelpers.jruby?
        before(:all) do
          skip "Dynamic instrumentation is not supported on JRuby"
        end
      end
      if RUBY_VERSION < "2.6"
        before(:all) do
          skip "Dynamic instrumentation requires Ruby 2.6 or higher"
        end
      end

      around do |example|
        check = true
        if Datadog::DI.instrumented_count > 0
          # Leaking instrumentations is a serious problem, but we want the
          # diagnostics to point to the root cause. If there are outstanding
          # instrumentations at the start of the test, the value at the end
          # is likely to be meaningless. But just in case the report that
          # is attached to the "root cause" test somehow disappears, warn
          # that there are outstanding instrumentations here.
          # They just produce noise in logs but not meaningless test failures.
          warn "DI: #{Datadog::DI.instrumented_count} outstanding instrumentations detected before test: #{Datadog::DI.instrumented_count(:method)} method instrumentations active, #{Datadog::DI.instrumented_count(:line)} line instrumentations active"
          check = false
        end

        example.run

        if check && Datadog::DI.instrumented_count > 0
          raise "DI: #{Datadog::DI.instrumented_count} outstanding instrumentations detected after test: #{Datadog::DI.instrumented_count(:method)} method instrumentations active, #{Datadog::DI.instrumented_count(:line)} line instrumentations active"
        end
      end
    end

    def mock_settings_for_di(&block)
      let(:settings) do
        double('settings').tap do |settings|
          allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
          if block
            instance_exec(settings, &block)
          end
        end
      end

      let(:di_settings) do
        double('di settings').tap do |settings|
          allow(settings).to receive(:internal).and_return(di_internal_settings)
        end
      end

      let(:di_internal_settings) do
        double('di internal settings')
      end
    end

    def with_code_tracking
      around do |example|
        Datadog::DI.activate_tracking!
        example.run
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

    def load_yaml_file(path, **opts)
      if RUBY_VERSION < '3.1'
        opts.delete(:permitted_classes)
      end
      YAML.load_file(path, **opts)
    end
  end

  module InstanceMethods
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

    def instance_double_agent_settings
      instance_double(Datadog::Core::Configuration::AgentSettings)
    end

    def instance_double_agent_settings_with_stubs
      instance_double(
        Datadog::Core::Configuration::AgentSettings,
        hostname: "test-host", port: 9000, timeout_seconds: 1, ssl: false
      )
    end
  end
end

module ProbeNotifierWorkerLeakDetector
  class << self
    attr_accessor :installed
    attr_accessor :workers

    def verify!
      ProbeNotifierWorkerLeakDetector.workers.each do |(worker, example)|
        warn "Leaked ProbeNotifierWorkerLeakDetector #{worker} from #{example.file_path}: #{example.full_description}"
      end
    end
  end

  ProbeNotifierWorkerLeakDetector.workers = []

  def start
    ProbeNotifierWorkerLeakDetector.workers << [self, RSpec.current_example]
    super
  end

  def stop(*args)
    ProbeNotifierWorkerLeakDetector.workers.delete_if do |(worker, example)|
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
  if RUBY_VERSION >= '2.6'
    config.before do
      if defined?(Datadog::DI::ProbeNotifierWorker) && !ProbeNotifierWorkerLeakDetector.installed
        Datadog::DI::ProbeNotifierWorker.send(:prepend, ProbeNotifierWorkerLeakDetector)
        ProbeNotifierWorkerLeakDetector.installed = true
      end
    end

    config.after do |example|
      ProbeNotifierWorkerLeakDetector.verify!
    end
  end
end
