# typed: false

require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'stringio'
require 'securerandom'
require 'webrick'

require 'ddtrace/transport/http'
require 'datadog/profiling'
require 'datadog/profiling/transport/http'
require 'ddtrace/transport/http/adapters/net'

RSpec.describe 'Adapters::Net profiling integration tests' do
  before { skip_if_profiling_not_supported(self) }

  let(:settings) { Datadog::Core::Configuration::Settings.new }

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
          'version' => '3',
          'start' => kind_of(String),
          'end' => kind_of(String),
          'data[rubyprofile.pprof]' => kind_of(String),
          'family' => 'ruby',
        )

        tags = body['tags[]'].list
        expect(tags).to include(
          /runtime:ruby/o,
          /runtime-id:#{uuid_regex.source}/,
          /runtime_engine:#{Datadog::Core::Environment::Ext::LANG_ENGINE}/o,
          /runtime_platform:#{Datadog::Core::Environment::Ext::LANG_PLATFORM}/o,
          /runtime_version:#{Datadog::Core::Environment::Ext::LANG_VERSION}/o,
          /process_id:#{Process.pid}/o,
          /profiler_version:#{Datadog::Core::Environment::Ext::TRACER_VERSION}/o,
          /language:ruby/o,
          'test_tag:test_value'
        )

        if Datadog::Core::Environment::Container.container_id
          container_id = Datadog::Core::Environment::Container.container_id[0..11]
          expect(tags).to include(/host:#{container_id}/)
        end
      end

      context 'when code provenance data is available' do
        let(:flush) do
          get_test_profiling_flush(
            code_provenance: Datadog::Profiling::Collectors::CodeProvenance.new.refresh.generate_json
          )
        end

        it 'sends profiles with code provenance data successfully' do
          client.send_profiling_flush(flush)

          boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
          body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)

          code_provenance_data = JSON.parse(
            Datadog::Core::Utils::Compression.gunzip(
              body.fetch('data[code-provenance.json]')
            )
          )

          expect(code_provenance_data)
            .to include('v1' => array_including(hash_including('kind' => 'library', 'name' => 'ddtrace')))
        end
      end
    end

    context 'via agent' do
      before do
        settings.agent.host = hostname
        settings.agent.port = port
      end

      let(:client) do
        Datadog::Profiling::Transport::HTTP.default(
          profiling_upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
          agent_settings: agent_settings
        )
      end

      let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings) }

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
        stub_const('Datadog::Profiling::OldExt::Transport::HTTP::URI_TEMPLATE_DD_API', "http://%s:#{port}/")
      end

      let(:api_key) { SecureRandom.uuid }
      let(:client) do
        Datadog::Profiling::Transport::HTTP.default(
          profiling_upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
          agent_settings: double('agent_settings which should not be used'),
          api_key: api_key,
          site: hostname,
          agentless_allowed: true
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

  def get_test_profiling_flush(code_provenance: nil)
    start = Time.now.utc
    finish = start + 10

    pprof_recorder = instance_double(
      Datadog::Profiling::StackRecorder,
      serialize: [start, finish, 'fake_compressed_encoded_pprof_data'],
    )

    code_provenance_collector =
      if code_provenance
        instance_double(Datadog::Profiling::Collectors::CodeProvenance, generate_json: code_provenance).tap do |it|
          allow(it).to receive(:refresh).and_return(it)
        end
      end

    Datadog::Profiling::Exporter.new(
      pprof_recorder: pprof_recorder,
      code_provenance_collector: code_provenance_collector,
    ).flush
  end
end
