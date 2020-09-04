require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'stringio'
require 'securerandom'
require 'thread'
require 'webrick'

require 'ddtrace/transport/http'
require 'ddtrace/profiling'
require 'ddtrace/profiling/transport/http'
require 'ddtrace/transport/http/adapters/net'

RSpec.describe 'Adapters::Net profiling integration tests' do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }
  before { skip 'Profiling is not supported.' unless Datadog::Profiling.supported? }

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

  describe 'when sending profiles through Net::HTTP adapter' do
    include_context 'HTTP server'

    let(:flush) { get_test_profiling_flush }

    shared_examples_for 'profile HTTP request' do
      subject(:request) { messages.first }

      it 'sends profiles successfully' do
        client.send_profiling_flush(flush)

        expect(request.header).to include(
          'datadog-meta-lang' => [Datadog::Ext::Runtime::LANG],
          'datadog-meta-lang-version' => [Datadog::Ext::Runtime::LANG_VERSION],
          'datadog-meta-lang-interpreter' => [Datadog::Ext::Runtime::LANG_INTERPRETER],
          'datadog-meta-tracer-version' => [Datadog::Ext::Runtime::TRACER_VERSION],
          'content-type' => [%r{^multipart\/form-data; boundary=(.+)}]
        )

        unless Datadog::Runtime::Container.container_id.nil?
          expect(request.header).to include(
            'datadog-container-id' => [Datadog::Runtime::Container.container_id]
          )
        end

        expect(request.header['content-length'].first.to_i).to be > 0

        # Check body
        boundary = request['content-type'][%r{^multipart\/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)

        expect(body).to include(
          'runtime-id' => Datadog::Runtime::Identity.id,
          'recording-start' => kind_of(String),
          'recording-end' => kind_of(String),
          'data[0]' => kind_of(String),
          'types[0]' => /auto/,
          'runtime' => Datadog::Ext::Runtime::LANG_INTERPRETER,
          'format' => Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_FORMAT_PPROF
        )

        # rubocop:disable Metrics/LineLength
        tags = body["#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAGS}[]"].list
        expect(tags).to be_a_kind_of(Array)
        expect(tags).to include(
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME}:#{Datadog::Ext::Runtime::LANG_INTERPRETER}/,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME_VERSION}:#{Datadog::Ext::Runtime::LANG_VERSION}/,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_PROFILER_VERSION}:#{Datadog::Ext::Runtime::TRACER_VERSION}/,
          /#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_LANGUAGE}:#{Datadog::Ext::Runtime::LANG}/
        )

        if Datadog::Runtime::Container.container_id
          container_id = Datadog::Runtime::Container.container_id[0..11]
          expect(tags).to include(/#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_HOST}:#{container_id}/)
        end
      end
    end

    context 'via agent' do
      let(:client) do
        Datadog::Profiling::Transport::HTTP.default do |t|
          t.adapter adapter
        end
      end

      it_behaves_like 'profile HTTP request' do
        it 'is formatted for the agent' do
          client.send_profiling_flush(flush)
          expect(request.path).to eq('/profiling/v1/input')
          expect(request.header).to_not include('dd-api-key')
        end
      end
    end

    context 'via agentless' do
      let(:api_key) { SecureRandom.uuid }
      let(:client) do
        Datadog::Profiling::Transport::HTTP.default(site: hostname, api_key: api_key) do |t|
          t.adapter adapter
        end
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
