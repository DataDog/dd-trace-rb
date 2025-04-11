require 'spec_helper'

require 'stringio'
require 'webrick'

require 'datadog/tracing/transport/http'
require 'datadog/core/transport/http/adapters/unix_socket'

RSpec.describe 'Adapters::UnixSocket integration tests' do
  skip_unless_integration_testing_enabled

  subject(:adapter) { Datadog::Core::Transport::HTTP::Adapters::UnixSocket.new(**options) }

  let(:uds_path) { '/tmp/datadog_unix_test.sock' }
  let(:options) { { uds_path: uds_path, timeout: timeout } }
  let(:timeout) { 2 }

  shared_context 'Unix socket server' do
    # Server
    let(:server) { UNIXServer.new(uds_path) }
    let(:messages) { [] }

    # HTTP
    http_server do |http_server|
      http_server.mount_proc('/', &server_proc)
    end
    let(:server_proc) do
      proc do |req, res|
        messages << req
        res.body = '{}'
      end
    end

    def cleanup_socket
      File.delete(uds_path) if File.exist?(uds_path)
    end

    before do
      cleanup_socket
      server

      @unix_server_thread = Thread.start do
        begin
          sock = server.accept
          # TODO: webrick supports UDS listener to replace this manual code
          http_server.run(sock)
        rescue => e
          puts "UNIX server error!: #{e}"
        end
      end
    end

    after do
      unless RSpec.current_example.skipped?
        cleanup_socket

        @unix_server_thread.join
      end
    end
  end

  describe 'when sending traces through Unix socket client' do
    include_context 'Unix socket server'

    let(:logger) { logger_allowing_debug }

    let(:client) do
      Datadog::Tracing::Transport::HTTP.default(agent_settings: test_agent_settings, logger: logger) do |t|
        t.adapter adapter
      end
    end

    let(:traces) { get_test_traces(2) }

    it 'sends traces successfully' do
      client.send_traces(traces)

      expect(messages).to have(1).items
      messages.first.tap do |http_request|
        expect(http_request.header).to include(
          'datadog-meta-lang' => [Datadog::Core::Environment::Ext::LANG],
          'datadog-meta-lang-version' => [Datadog::Core::Environment::Ext::LANG_VERSION],
          'datadog-meta-lang-interpreter' => [Datadog::Core::Environment::Ext::LANG_INTERPRETER],
          'datadog-meta-tracer-version' => [Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION],
          'content-type' => ['application/msgpack'],
          'x-datadog-trace-count' => [traces.length.to_s]
        )

        unless Datadog::Core::Environment::Container.container_id.nil?
          expect(http_request.header).to include(
            'datadog-container-id' => [Datadog::Core::Environment::Container.container_id]
          )
        end

        expect(http_request.header['content-length'].first.to_i).to be > 0
      end
    end
  end
end
