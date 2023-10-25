require 'datadog/profiling/collectors/system_info'
require 'json-schema'

RSpec.describe Datadog::Profiling::Collectors::SystemInfo do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:system_info) { system_info_collector.system_info }

  subject(:system_info_collector) { described_class.new(settings) }

  describe '#refresh' do
    before do
      settings.service = 'test'
      settings.profiling.advanced.max_frames = 600
      settings.profiling.advanced.experimental_heap_enabled = true
    end

    it 'records useful system info in multiple categories' do
      system_info_collector.refresh

      expect(system_info).to match(
        {
          platform: hash_including(
            kernel_name: Datadog::Core::Environment::Platform.kernel_name,
          ),
          runtime: hash_including(
            engine: Datadog::Core::Environment::Identity.lang_engine,
          ),
          application: hash_including(
            service: settings.service,
          ),
          profiler: hash_including(
            version: Datadog::Core::Environment::Identity.tracer_version,
          ),
        }
      )
    end

    it 'records a sensible application start time' do
      system_info_collector.refresh

      now = Time.now

      # We approximate the start time to the loading time of system_info. For this not to be
      # too flaky, we just check an approximate order of magnitude and parsing format.
      parsed_start_time = Time.iso8601(system_info[:application][:start_time])
      expect(parsed_start_time).to be_between(now - 60 * 60, now)
    end

    it 'records profiler system info including a json dump of settings' do
      system_info_collector.refresh

      expect(system_info[:profiler][:settings][:advanced]).to match(
        a_hash_including(
          max_frames: 600,
          experimental_allocation_enabled: false,
          experimental_heap_enabled: true,
        )
      )
    end

    it 'caches unmutable info' do
      system_info_collector.refresh

      platform = system_info[:platform]
      runtime = system_info[:runtime]
      application = system_info[:application]
      profiler = system_info[:profiler]

      system_info_collector.refresh

      expect(system_info[:platform]).to be(platform)
      expect(system_info[:runtime]).to be(runtime)
      expect(system_info[:application]).to be(application)
      expect(system_info[:profiler]).to be(profiler)
    end

    it 'returns self' do
      expect(system_info_collector.refresh).to be system_info_collector
    end
  end
end
