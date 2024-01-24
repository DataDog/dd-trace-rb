require 'datadog/profiling/collectors/info'
require 'json-schema'

RSpec.describe Datadog::Profiling::Collectors::Info do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:info) { info_collector.info }

  subject(:info_collector) { described_class.new(settings) }

  describe '#refresh' do
    before do
      settings.service = 'test'
      settings.profiling.advanced.max_frames = 600
      settings.profiling.advanced.experimental_heap_enabled = true
    end

    it 'records useful info in multiple categories' do
      info_collector.refresh

      expect(info).to match(
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
      info_collector.refresh

      now = Time.now

      # We approximate the start time to the loading time of info. For this not to be
      # too flaky, we just check an approximate order of magnitude and parsing format.
      parsed_start_time = Time.iso8601(info[:application][:start_time])
      expect(parsed_start_time).to be_between(now - 60 * 60, now)
    end

    it 'records profiler info including a json dump of settings' do
      info_collector.refresh

      expect(info[:profiler][:settings][:advanced]).to match(
        a_hash_including(
          max_frames: 600,
          experimental_allocation_enabled: false,
          experimental_heap_enabled: true,
        )
      )
    end

    it 'caches unmutable info' do
      info_collector.refresh

      platform = info[:platform]
      runtime = info[:runtime]
      application = info[:application]
      profiler = info[:profiler]

      info_collector.refresh

      expect(info[:platform]).to be(platform)
      expect(info[:runtime]).to be(runtime)
      expect(info[:application]).to be(application)
      expect(info[:profiler]).to be(profiler)
    end

    it 'returns self' do
      expect(info_collector.refresh).to be info_collector
    end
  end
end
