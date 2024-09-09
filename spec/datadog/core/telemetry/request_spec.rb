require 'spec_helper'

require 'datadog/core/telemetry/request'

RSpec.describe Datadog::Core::Telemetry::Request do
  describe '.build_payload' do
    subject { described_class.build_payload(event, seq_id) }
    let(:event) { double('event', payload: payload, type: request_type) }
    let(:seq_id) { double('seq_id') }
    let(:payload) { double('payload') }
    let(:request_type) { double('request_type') }

    let(:api_version) { 'v2' }
    let(:debug) { false }
    let(:runtime_id) { Datadog::Core::Environment::Identity.id }
    let(:tracer_time) { Time.now.to_i }

    let(:application) do
      {
        env: env,
        language_name: language_name,
        language_version: language_version,
        runtime_name: runtime_name,
        runtime_version: runtime_version,
        service_name: service_name,
        service_version: service_version,
        tracer_version: tracer_version,
      }
    end

    let(:env) { 'env' }
    let(:language_name) { 'ruby' }
    let(:language_version) { RUBY_VERSION }
    let(:runtime_name) { RUBY_ENGINE }
    let(:runtime_version) { Datadog::Core::Environment::Ext::ENGINE_VERSION }
    let(:service_name) { 'service' }
    let(:service_version) { 'version' }
    let(:tracer_version) { Datadog::Core::Environment::Identity.gem_datadog_version_semver2 }

    let(:host) do
      {
        architecture: architecture,
        hostname: hostname,
        kernel_name: kernel_name,
        kernel_release: kernel_release,
        kernel_version: kernel_version,
      }
    end

    let(:architecture) { Datadog::Core::Environment::Platform.architecture }
    let(:hostname) { Datadog::Core::Environment::Platform.hostname }
    let(:kernel_name) { Datadog::Core::Environment::Platform.kernel_name }
    let(:kernel_release) { Datadog::Core::Environment::Platform.kernel_release }
    let(:kernel_version) { Datadog::Core::Environment::Platform.kernel_version }

    before do
      Datadog.configure do |c|
        c.env = env
        c.service = service_name
        c.version = service_version
      end
    end

    it do
      is_expected.to eq(
        api_version: api_version,
        application: application,
        debug: debug,
        host: host,
        payload: payload,
        request_type: request_type,
        runtime_id: runtime_id,
        seq_id: seq_id,
        tracer_time: tracer_time,
      )
    end

    context 'when Datadog::CI is loaded and ci mode is enabled' do
      before do
        stub_const('Datadog::CI::VERSION::STRING', '1.2.3')
        expect(Datadog).to receive(:configuration).and_return(
          double(
            'configuration',
            ci: double('ci', enabled: true),
            env: env,
            service: service_name,
            version: service_version
          )
        )
      end

      it do
        is_expected.to eq(
          api_version: api_version,
          application: application.merge(tracer_version: "#{tracer_version}-ci-1.2.3"),
          debug: debug,
          host: host,
          payload: payload,
          request_type: request_type,
          runtime_id: runtime_id,
          seq_id: seq_id,
          tracer_time: tracer_time,
        )
      end
    end
  end
end
