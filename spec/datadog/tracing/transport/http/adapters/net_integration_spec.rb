require 'spec_helper'

require 'stringio'
require 'webrick'

require 'datadog/tracing/transport/http'
require 'datadog/core/transport/http/adapters/net'

RSpec.describe 'Adapters::Net tracing integration tests' do
  before { skip('Skipping test as ENV["TEST_DATADOG_INTEGRATION"] is not set') unless ENV['TEST_DATADOG_INTEGRATION'] }

  subject(:adapter) { Datadog::Core::Transport::HTTP::Adapters::Net.new(agent_settings) }

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
      adapter: nil,
      ssl: false,
      uds_path: nil,
      hostname: hostname,
      port: port,
      timeout_seconds: 30,
    )
  end

  shared_context 'HTTP server' do
    # HTTP
    let(:server) do
      WEBrick::HTTPServer.new(
        Port: 0,
        Logger: log,
        AccessLog: access_log,
        StartCallback: -> { init_signal.push(1) }
      )
    end
    let(:hostname) { '127.0.0.1' }
    let(:port) { server[:Port] }
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
      @server_thread = Thread.new { server.start }
      init_signal.pop
    end

    after do
      unless RSpec.current_example.skipped?
        # When the test is skipped, server has not been initialized and @server_thread would be nil; thus we only
        # want to touch them when the test actually run, otherwise we would cause the server to start (incorrectly)
        # and join to be called on a nil @server_thread
        server.shutdown
        @server_thread.join
      end
    end
  end

  describe 'when sending traces through Net::HTTP adapter' do
    include_context 'HTTP server'

    let(:client) do
      Datadog::Tracing::Transport::HTTP.default do |t|
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
        expect(http_request.body.length).to be > 0
      end
    end
  end
end
