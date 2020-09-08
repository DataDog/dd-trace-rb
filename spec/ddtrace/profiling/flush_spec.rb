RSpec.describe Datadog::Profiling::Flush do
  describe '#new' do
    context 'given no arguments' do
      subject(:identifier) { described_class.new }

      it do
        is_expected.to have_attributes(
          start: nil,
          finish: nil,
          event_groups: nil,
          event_count: nil,
          runtime_id: Datadog::Runtime::Identity.id,
          service: Datadog.configuration.service,
          env: Datadog.configuration.env,
          version: Datadog.configuration.version,
          host: Datadog::Runtime::Socket.hostname,
          language: Datadog::Runtime::Identity.lang,
          runtime_engine: Datadog::Runtime::Identity.lang_engine,
          runtime_platform: Datadog::Runtime::Identity.lang_platform,
          runtime_version: Datadog::Runtime::Identity.lang_version,
          profiler_version: Datadog::Runtime::Identity.tracer_version
        )
      end
    end

    context 'given full arguments' do
      subject(:identifier) do
        described_class.new(
          start,
          finish,
          event_groups,
          event_count,
          runtime_id,
          service,
          env,
          version,
          host,
          language,
          runtime_engine,
          runtime_platform,
          runtime_version,
          profiler_version
        )
      end

      let(:start) { double('start') }
      let(:finish) { double('finish') }
      let(:event_groups) { double('event_groups') }
      let(:event_count) { double('event_count') }
      let(:runtime_id) { double('runtime_id') }
      let(:service) { double('service') }
      let(:env) { double('env') }
      let(:version) { double('version') }
      let(:host) { double('host') }
      let(:language) { double('language') }
      let(:runtime_engine) { double('runtime_engine') }
      let(:runtime_platform) { double('runtime_platform') }
      let(:runtime_version) { double('runtime_version') }
      let(:profiler_version) { double('profiler_version') }

      it do
        is_expected.to have_attributes(
          start: start,
          finish: finish,
          event_groups: event_groups,
          event_count: event_count,
          runtime_id: runtime_id,
          service: service,
          env: env,
          version: version,
          host: host,
          language: language,
          runtime_engine: runtime_engine,
          runtime_platform: runtime_platform,
          runtime_version: runtime_version,
          profiler_version: profiler_version
        )
      end
    end
  end
end
