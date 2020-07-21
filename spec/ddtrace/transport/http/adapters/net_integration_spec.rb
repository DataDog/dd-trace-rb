require 'spec_helper'

require 'stringio'
require 'thread'
require 'webrick'

require 'ddtrace/transport/http'
require 'ddtrace/transport/http/adapters/net'

RSpec.describe 'Adapters::Net tracing integration tests' do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  subject(:adapter) { Datadog::Transport::HTTP::Adapters::Net.new(hostname, port) }

  shared_context 'HTTP server' do
    # HTTP
    let(:server) do
      WEBrick::HTTPServer.new(
        Port: port,
        Logger: log,
        AccessLog: access_log,
        StartCallback: -> { init_signal.push(1) }
      )
    end
    let(:hostname) { '127.0.0.1' }
    let(:port) { 6218 }
    let(:log) { WEBrick::Log.new(log_buffer) }
    let(:log_buffer) { StringIO.new }
    let(:access_log) { [[log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
    let(:server_proc) do
      proc do |req, res|
        messages << req.tap { req.body } # Read body, store message before socket closes.
        res.body = '{}'
      end
    end
    let(:init_signal) { Queue.new }

    let(:messages) { [] }

    before do
      server.mount_proc('/', &server_proc)
      Thread.new { server.start }
      init_signal.pop
    end

    after { server.shutdown }
  end

  describe 'when sending traces through Net::HTTP adapter' do
    include_context 'HTTP server'

    let(:client) do
      Datadog::Transport::HTTP.default do |t|
        t.adapter adapter
      end
    end

    let(:traces) { get_test_traces(2) }

    it 'sends traces successfully' do
      client.send_traces(traces)

      expect(messages).to have(1).items
      messages.first.tap do |http_request|
        expect(http_request.header).to include(
          'datadog-meta-lang' => [Datadog::Ext::Runtime::LANG],
          'datadog-meta-lang-version' => [Datadog::Ext::Runtime::LANG_VERSION],
          'datadog-meta-lang-interpreter' => [Datadog::Ext::Runtime::LANG_INTERPRETER],
          'datadog-meta-tracer-version' => [Datadog::Ext::Runtime::TRACER_VERSION],
          'content-type' => ['application/msgpack'],
          'x-datadog-trace-count' => [traces.length.to_s]
        )

        unless Datadog::Runtime::Container.container_id.nil?
          expect(http_request.header).to include(
            'datadog-container-id' => [Datadog::Runtime::Container.container_id]
          )
        end

        expect(http_request.header['content-length'].first.to_i).to be > 0
        expect(http_request.body.length).to be > 0
      end
    end
  end
end
