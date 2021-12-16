# typed: false
RSpec.describe Datadog::Profiling::Flush do
  describe '#new' do
    let(:start) { double('start') }
    let(:finish) { double('finish') }
    let(:event_groups) { double('event_groups') }
    let(:event_count) { double('event_count') }

    context 'given only required arguments' do
      subject(:identifier) {
        described_class.new(start: start, finish: finish, event_groups: event_groups, event_count: event_count)
      }

      it do
        is_expected.to have_attributes(
          start: start,
          finish: finish,
          event_groups: event_groups,
          event_count: event_count,
          runtime_id: Datadog::Core::Environment::Identity.id,
          service: Datadog.configuration.service,
          env: Datadog.configuration.env,
          version: Datadog.configuration.version,
          host: Datadog::Core::Environment::Socket.hostname,
          language: Datadog::Core::Environment::Identity.lang,
          runtime_engine: Datadog::Core::Environment::Identity.lang_engine,
          runtime_platform: Datadog::Core::Environment::Identity.lang_platform,
          runtime_version: Datadog::Core::Environment::Identity.lang_version,
          profiler_version: Datadog::Core::Environment::Identity.tracer_version,
          tags: Datadog.configuration.tags
        )
      end
    end

    context 'given full arguments' do
      subject(:identifier) do
        described_class.new(
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
          profiler_version: profiler_version,
          tags: tags,
        )
      end

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
      let(:tags) { double('tags') }

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
          profiler_version: profiler_version,
          tags: tags,
        )
      end
    end
  end
end
