require 'spec_helper'

require 'stringio'
require 'thread'
require 'webrick'

require 'ddtrace/transport/http'
require 'ddtrace/transport/http/adapters/unix_socket'

RSpec.describe 'Adapters::UnixSocket integration tests' do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  subject(:adapter) { Datadog::Transport::HTTP::Adapters::UnixSocket.new(filepath, options) }

  let(:filepath) { '/tmp/ddtrace_unix_test.sock' }
  let(:options) { { timeout: timeout } }
  let(:timeout) { 2 }

  shared_context 'Unix socket server' do
    # Server
    let(:server) { UNIXServer.new(filepath) }
    let(:messages) { [] }

    # HTTP
    let(:http) do
      WEBrick::HTTPServer.new(
        Logger: log,
        AccessLog: access_log,
        StartCallback: -> { http_init_signal.push(1) }
      )
    end
    let(:log) { WEBrick::Log.new(log_buffer) }
    let(:log_buffer) { StringIO.new }
    let(:access_log) { [[log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
    let(:server_proc) do
      proc do |req, res|
        messages << req
        res.body = '{}'
      end
    end
    let(:http_init_signal) { Queue.new }

    def cleanup_socket
      File.delete(filepath) if File.exist?(filepath)
    end

    before do
      cleanup_socket
      server
      http.mount_proc('/', &server_proc)

      @http_server_thread = Thread.start do
        http.start
      end

      @unix_server_thread = Thread.start do
        begin
          sock = server.accept
          http.run(sock)
        rescue => e
          puts "UNIX server error!: #{e}"
        end
      end

      http_init_signal.pop
    end

    after do
      http.shutdown
      cleanup_socket
    end
  end

  describe 'when sending traces through Unix socket client' do
    include_context 'Unix socket server'

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
      end
    end
  end
end
