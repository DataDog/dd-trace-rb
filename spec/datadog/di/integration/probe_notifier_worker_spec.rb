require "datadog/di/spec_helper"
require 'datadog/di'
require "datadog/di/probe_notifier_worker"

# standard tries to wreck regular expressions in this fiel
# rubocop:disable Style/PercentLiteralDelimiters
# rubocop:disable Layout/LineContinuationSpacing

RSpec.describe Datadog::DI::ProbeNotifierWorker do
  di_test

  let(:worker) do
    described_class.new(settings, logger, agent_settings: agent_settings)
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.agent.host = 'localhost'
      settings.agent.port = http_server_port
      settings.agent.use_ssl = false
      settings.agent.timeout_seconds = 1
    end
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  di_logger_double

  let(:diagnostics_payloads) { [] }
  let(:input_payloads) { [] }

  http_server do |http_server|
    @received_snapshot_count = 0
    @received_snapshot_bytes = 0

    http_server.mount_proc('/debugger/v1/diagnostics') do |req, res|
      # This request is a multipart form post
      expect(req.content_type).to match(%r,^multipart/form-data;,)
      diagnostics_payloads << req.body
    end

    http_server.mount_proc('/debugger/v1/input') do |req, res|
      expect(req.content_type).to eq('application/json')
      payload = JSON.parse(req.body)
      input_payloads << payload
    end
  end

  after do
    worker.stop
  end

  context 'probe status' do
    let(:installed_payload) do
      {ddsource: 'dd_debugger',
       debugger: {
         diagnostics: {
           parentId: nil,
           probeId: String,
           probeVersion: 0,
           runtimeId: 'test runtime id',
           status: 'INSTALLED',
         }
       },
       message: 'test message',
       service: 'rspec',
       timestamp: 1234567890,}.freeze
    end

    it 'sends expected payload' do
      worker.add_status(installed_payload)
      worker.flush
      expect(worker.send(:thread)).to be_alive

      expect(diagnostics_payloads.length).to be 1
      expect(diagnostics_payloads.first.gsub("\r\n", "\n").strip).to match(%r~\
----[-\w]+
Content-Disposition: form-data; name="event"; filename="event.json"
Content-Length: 226
Content-Type: application/json
Content-Transfer-Encoding: binary

\[{"ddsource":"dd_debugger","debugger":{"diagnostics":{"parentId":null,"probeId":"String","probeVersion":0,"runtimeId":"test runtime id","status":"INSTALLED"}},"message":"test message","service":"rspec","timestamp":1234567890}\]
----[-\w]+\
~)
    end
  end

  context 'probe snapshot' do
    let(:snapshot_payload) do
      {
        path: '/debugger/v1/input',
        # We do not have active span/trace in the test.
        "dd.span_id": nil,
        "dd.trace_id": nil,
        "debugger.snapshot": {
          captures: nil,
          evaluationErrors: [],
          id: 'test id',
          language: 'ruby',
          probe: {
            id: '11',
            location: {
              method: 'target_method',
              type: 'EverythingFromRemoteConfigSpecTestClass',
            },
            version: 0,
          },
          stack: ['test entry'],
          timestamp: 1234567890,
        },
        ddsource: 'dd_debugger',
        duration: 123.45,
        host: nil,
        logger: {
          method: 'target_method',
          name: nil,
          thread_id: nil,
          thread_name: 'Thread.main',
          version: 2,
        },
        message: nil,
        service: 'rspec',
        timestamp: 1234567890,
      }.freeze
    end

    it 'sends expected payload' do
      worker.add_snapshot(snapshot_payload)
      worker.flush
      expect(worker.send(:thread)).to be_alive

      expect(input_payloads.length).to be 1
      # deep stringify keys
      expect(input_payloads.first).to eq([JSON.parse(snapshot_payload.to_json)])
    end
  end
end

# rubocop:enable Style/PercentLiteralDelimiters
# rubocop:enable Layout/LineContinuationSpacing
