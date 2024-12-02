module DIHelpers
  module ClassMethods
    def ruby_2_only
      if RUBY_VERSION >= '3'
        before(:all) do
          skip "Test is only for Ruby 2"
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
