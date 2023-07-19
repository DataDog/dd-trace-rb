require 'spec_helper'

RSpec.describe Datadog::Tracing::Remote do
  describe 'integration', :integration do
    shared_context 'using the test agent' do
      let(:test_agent_host) { ENV['DD_TEST_AGENT_HOST'] || 'localhost' }
      let(:test_agent_port) { ENV['DD_TEST_AGENT_PORT'] || 9126 }
      around do |example|
        ClimateControl.modify('DD_AGENT_HOST' => test_agent_host, 'DD_TRACE_AGENT_PORT' => test_agent_port.to_s) do
          example.run
        end
      end
    end

    include_context 'using the test agent'

    before do |example|
      Net::HTTP.post(URI.parse("http://#{test_agent_host}:#{test_agent_port}/test/session/responses/config/path"),
                     { path: "datadog/1/APM_TRACING/config_id/lib_config", msg: payload }.to_json)
      # , { 'X-Datadog-Test-Session-Token' => example.description }
      # TODO: let's add a session token, to ensure separation
      # { 'X-Datadog-Test-Session-Token' => x.example.metadata[:example_group][:full_description] }

      Datadog.configure do |c|
        c.tracing.instance = tracer
        c.diagnostics.debug = true
        # c.remote.poll_interval_seconds = Float::MIN
      end
    end

    let(:payload) do
      {
        "action": "enable",
        "service_target": { "service": 'test-service', "env": 'test-env' },
        "lib_config": {
          # v1 dynamic config
          "tracing_sampling_rate": tracing_sampling_rate,
          "log_injection_enabled": log_injection_enabled,
          "tracing_header_tags": tracing_header_tags,
          # v2 dynamic config
          "runtime_metrics_enabled": nil,
          "tracing_debug": nil,
          "tracing_service_mapping": nil,
          "tracing_sampling_rules": nil,
          "span_sampling_rules": nil,
          "data_streams_enabled": nil,
        },
      }
    end

    let(:tracing_sampling_rate) { nil }
    let(:log_injection_enabled) { nil }
    let(:tracing_header_tags) { nil }

    it do
      # allow(Datadog.send(:components).remote.client).to receive(:sync).and_wrap_original do |method|
      #   @sync_called = true
      #   method.call
      # end
      #
      # try_wait_until { @sync_called }

    end

    context 'for tracing_header_tags' do
      let(:tracing_header_tags) { [{ 'header' => 'test-header', 'tag_name' => '' }] }
      it do
        Datadog::Tracing.trace('test'){}
        sleep 3600
        expect(fetch_spans).to eq(1)
      end
    end
  end
end
