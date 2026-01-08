require "datadog/di/spec_helper"
require 'datadog/di'
require "datadog/di/probe_notifier_worker"

# standard tries to wreck regular expressions in this file
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
  let(:missing_endpoint_payloads) { [] }
  let(:unused_endpoint_requests) { [] }

  def define_diagnostics_endpoint(http_server)
    http_server.mount_proc('/debugger/v1/diagnostics') do |req, res|
      # This request is a multipart form post
      expect(req.content_type).to match(%r,^multipart/form-data;,)
      diagnostics_payloads << req.body
    end
  end

  def define_input_endpoint(http_server, path)
    @received_snapshot_count = 0
    @received_snapshot_bytes = 0

    http_server.mount_proc(path) do |req, res|
      expect(req.content_type).to eq('application/json')
      payload = JSON.parse(req.body)

      query = CGI.parse(req.query_string)
      expect(query).to have_key('ddtags')
      tags = query['ddtags'].first.split(',')
      # We do not need to assert on everything in tags - this is done in
      # unit tests elsewhere.
      expect(tags).to include('language:ruby')
      expect(tags).to include("debugger_version:#{Gem.loaded_specs["datadog"].version}")

      input_payloads << {body: payload, tags: tags}
    end
  end

  def define_missing_endpoint(http_server, path)
    http_server.mount_proc(path) do |req, res|
      expect(req.content_type).to eq('application/json')
      payload = JSON.parse(req.body)

      missing_endpoint_payloads << {body: payload}

      res.status = 404
      res.body = "endpoint not implemented: #{path}"
    end
  end

  def define_unused_endpoint(http_server, path)
    http_server.mount_proc(path) do |req, res|
      # We cannot simply raise an exception here because that will be
      # caught by webrick and converted to error code, and most transports
      # do not require requests to agent to succeed.
      # Hence we need to have a different way to verify that this
      # endpoint is not called.
      unused_endpoint_requests << req

      # But, for good measure, let's also raise an exception and fail
      # the request.
      raise "This endpoint should not be invoked: #{path}"
    end
  end

  after do
    worker.stop
  end

  context 'probe status' do
    http_server do |http_server|
      define_diagnostics_endpoint(http_server)
    end

    after do
      expect(unused_endpoint_requests).to be_empty
    end

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
    after do
      expect(unused_endpoint_requests).to be_empty
    end

    let(:snapshot_payload) do
      # Not a real snapshot payload.
      # We specify the payload as argument to probe notifier worker,
      # the worker in turn sends it over the wire without validation/changes.
      # Use a dummy payload to avoid confusion with respect to whether
      # the contents is correct as far as backend expectations.
      {
        snapshot: 'payload',
      }.freeze
    end

    context 'when /debugger/v2/input endpoint is available' do
      http_server do |http_server|
        define_diagnostics_endpoint(http_server)
        define_input_endpoint(http_server, '/debugger/v2/input')
        # In practice, an agent implementing v2 endpoint will also implement
        # the v1 endpoint. We set v1 endpoint as missing to receive the
        # payload into a different variable for assertions.
        define_missing_endpoint(http_server, '/debugger/v1/diagnostics')
        # Also define /debugger/v1/input as missing.
        # We should not be using this endpoint for anything going forward,
        # assert this.
        define_unused_endpoint(http_server, '/debugger/v1/input')
      end

      it 'sends expected payload to v2 endpoint only' do
        worker.add_snapshot(snapshot_payload)
        worker.flush
        expect(worker.send(:thread)).to be_alive

        expect(input_payloads.length).to be 1
        # deep stringify keys
        expect(input_payloads.first[:body]).to eq([JSON.parse(snapshot_payload.to_json)])

        expect(missing_endpoint_payloads).to be_empty
      end

      context 'when git environment variables are set' do
        with_env 'DD_GIT_REPOSITORY_URL' => 'http://foo',
          'DD_GIT_COMMIT_SHA' => '1234hash'

        before do
          Datadog::Core::Environment::Git.reset_for_tests
          Datadog::Core::TagBuilder.reset_for_tests
        end

        it 'includes SCM tags in payload' do
          worker.add_snapshot(snapshot_payload)
          worker.flush
          expect(worker.send(:thread)).to be_alive

          expect(input_payloads.length).to be 1
          # deep stringify keys
          expect(input_payloads.first[:body]).to eq([JSON.parse(snapshot_payload.to_json)])

          tags = input_payloads.first[:tags]
          expect(tags).to include('git.repository_url:http://foo')
          expect(tags).to include('git.commit.sha:1234hash')
        end
      end
    end

    context 'when /debugger/v2/input endpoint is not available' do
      http_server do |http_server|
        define_diagnostics_endpoint(http_server)
        define_input_endpoint(http_server, '/debugger/v1/diagnostics')
        define_missing_endpoint(http_server, '/debugger/v2/input')
        # Also define /debugger/v1/input as missing.
        # We should not be using this endpoint for anything going forward,
        # assert this.
        define_unused_endpoint(http_server, '/debugger/v1/input')
      end

      it 'sends expected payload to v2 then v1 endpoint' do
        allow(logger).to receive(:debug)

        worker.add_snapshot(snapshot_payload)
        worker.flush
        expect(worker.send(:thread)).to be_alive

        expect(input_payloads.length).to be 1
        # deep stringify keys
        expect(input_payloads.first[:body]).to eq([JSON.parse(snapshot_payload.to_json)])

        expect(missing_endpoint_payloads.length).to be 1
        expect(missing_endpoint_payloads.first[:body]).to eq([JSON.parse(snapshot_payload.to_json)])

        expect(logger).to have_lazy_debug_logged(/send_request :input failed:.*endpoint not implemented/)
      end
    end
  end
end

# rubocop:enable Style/PercentLiteralDelimiters
# rubocop:enable Layout/LineContinuationSpacing
