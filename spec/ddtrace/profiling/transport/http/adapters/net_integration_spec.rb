require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'stringio'
require 'securerandom'
require 'webrick'

require 'ddtrace/transport/http'
require 'ddtrace/profiling'
require 'ddtrace/profiling/transport/http'
require 'ddtrace/transport/http/adapters/net'

RSpec.describe 'Adapters::Net profiling integration tests' do
  before do
    skip 'TEST_DATADOG_INTEGRATION is not defined' unless ENV['TEST_DATADOG_INTEGRATION']
    skip 'Profiling is not supported.' unless Datadog::Profiling.supported?
  end

  let(:settings) { Datadog::Configuration::Settings.new }

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

  describe 'when sending profiles through Net::HTTP adapter' do
    include_context 'HTTP server'

    let(:flush) { get_test_profiling_flush }

    shared_examples_for 'profile HTTP request' do
      subject(:request) { messages.first }

      let(:tags) { { 'test_tag' => 'test_value' } }

      before do
        allow(Datadog.configuration).to receive(:tags).and_return(tags)
      end

      # rubocop:disable Layout/LineLength
      it 'sends profiles successfully' do
        client.send_profiling_flush(flush)

        expect(request.header).to include(
          'datadog-meta-lang' => [Datadog::Core::Environment::Ext::LANG],
          'datadog-meta-lang-version' => [Datadog::Core::Environment::Ext::LANG_VERSION],
          'datadog-meta-lang-interpreter' => [Datadog::Core::Environment::Ext::LANG_INTERPRETER],
          'datadog-meta-tracer-version' => [Datadog::Core::Environment::Ext::TRACER_VERSION],
          'content-type' => [%r{^multipart/form-data; boundary=(.+)}]
        )

        unless Datadog::Core::Environment::Container.container_id.nil?
          expect(request.header).to include(
            'datadog-container-id' => [Datadog::Core::Environment::Container.container_id]
          )
        end

        expect(request.header['content-length'].first.to_i).to be > 0

        # Check body
        boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)

        expect(body).to include(
          'runtime-id' => Datadog::Core::Environment::Identity.id,
          'recording-start' => kind_of(String),
          'recording-end' => kind_of(String),
          'data[0]' => kind_of(String),
          'types[0]' => /auto/,
          'runtime' => Datadog::Core::Environment::Ext::LANG,
          'format' => Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_FORMAT_PPROF
        )

        tags = body["#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAGS}[]"].list
        expect(tags).to include(
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME}:#{Datadog::Core::Environment::Ext::LANG}/o,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME_ID}:#{uuid_regex.source}/,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME_ENGINE}:#{Datadog::Core::Environment::Ext::LANG_ENGINE}/o,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME_PLATFORM}:#{Datadog::Core::Environment::Ext::LANG_PLATFORM}/o,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME_VERSION}:#{Datadog::Core::Environment::Ext::LANG_VERSION}/o,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_PID}:#{Process.pid}/o,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_PROFILER_VERSION}:#{Datadog::Core::Environment::Ext::TRACER_VERSION}/o,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_LANGUAGE}:#{Datadog::Core::Environment::Ext::LANG}/o,
          'test_tag:test_value'
        )

        if Datadog::Core::Environment::Container.container_id
          container_id = Datadog::Core::Environment::Container.container_id[0..11]
          expect(tags).to include(/#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_HOST}:#{container_id}/)
        end
      end
      # rubocop:enable Layout/LineLength
    end

    context 'via agent' do
      before do
        settings.tracer.hostname = hostname
        settings.tracer.port = port
      end

      let(:client) do
        Datadog::Profiling::Transport::HTTP.default(
          profiling_upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
          agent_settings: agent_settings
        )
      end

      let(:agent_settings) { Datadog::Configuration::AgentSettingsResolver.call(settings) }

      it_behaves_like 'profile HTTP request' do
        it 'is formatted for the agent' do
          client.send_profiling_flush(flush)
          expect(request.path).to eq('/profiling/v1/input')
          expect(request.header).to_not include('dd-api-key')
        end
      end
    end

    context 'via agentless' do
      before do
        stub_const('Datadog::Ext::Profiling::Transport::HTTP::URI_TEMPLATE_DD_API', "http://%s:#{port}/")
      end

      let(:api_key) { SecureRandom.uuid }
      let(:client) do
        Datadog::Profiling::Transport::HTTP.default(
          profiling_upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
          api_key: api_key,
          site: hostname
        )
      end

      it_behaves_like 'profile HTTP request' do
        it 'is formatted for the API' do
          client.send_profiling_flush(flush)
          expect(request.path).to eq('/v1/input')
          expect(request.header).to include(
            'dd-api-key' => [api_key]
          )
        end
      end
    end
  end
end
