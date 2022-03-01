# typed: ignore

require 'datadog/profiling/spec_helper'

require 'datadog/profiling/http_transport'
require 'datadog/profiling'

require 'webrick'
require 'socket'

# Design note for this class's specs: from the Ruby code side, we're treating the `_native_` methods as an API
# between the Ruby code and the native methods, and thus in this class we have a bunch of tests to make sure the
# native methods are invoked correctly.
#
# We also have "integration" specs, where we exercise the Ruby code together with the C code and libddprof to ensure
# that things come out of libddprof as we expected.
RSpec.describe Datadog::Profiling::HttpTransport do
  before { skip_if_profiling_not_supported(self) }

  subject(:http_transport) do
    described_class.new(
      agent_settings: agent_settings,
      site: site,
      api_key: api_key,
      tags: tags,
      upload_timeout_seconds: upload_timeout_seconds,
    )
  end

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
      adapter: adapter,
      uds_path: uds_path,
      ssl: ssl,
      hostname: hostname,
      port: port,
      deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc,
      timeout_seconds: nil,
    )
  end
  let(:adapter) { Datadog::Transport::Ext::HTTP::ADAPTER }
  let(:uds_path) { nil }
  let(:ssl) { false }
  let(:hostname) { '192.168.0.1' }
  let(:port) { '12345' }
  let(:deprecated_for_removal_transport_configuration_proc) { nil }
  let(:site) { nil }
  let(:api_key) { nil }
  let(:tags) { { 'tag_a' => 'value_a', 'tag_b' => 'value_b' } }
  let(:upload_timeout_seconds) { 123 }

  let(:flush) do
    Datadog::Profiling::Flush.new(
      start: start,
      finish: finish,
      pprof_file_name: pprof_file_name,
      pprof_data: pprof_data,
      code_provenance_file_name: code_provenance_file_name,
      code_provenance_data: code_provenance_data,
    )
  end
  let(:start_timestamp) { '2022-02-07T15:59:53.987654321Z' }
  let(:end_timestamp) { '2023-11-11T16:00:00.123456789Z' }
  let(:start)  { Time.iso8601(start_timestamp) }
  let(:finish) { Time.iso8601(end_timestamp) }
  let(:pprof_file_name) { 'the_pprof_file_name.pprof' }
  let(:pprof_data) { 'the_pprof_data' }
  let(:code_provenance_file_name) { 'the_code_provenance_file_name.json' }
  let(:code_provenance_data) { 'the_code_provenance_data' }

  describe '#initialize' do
    let(:tags_as_array) { [%w[tag_a value_a], %w[tag_b value_b]] }

    context 'when agent_settings are provided' do
      it 'creates an agent exporter with the given settings' do
        expect(described_class)
          .to receive(:_native_create_agent_exporter)
          .with('http://192.168.0.1:12345/', tags_as_array)
          .and_return([:ok, :dummy_exporter])

        http_transport
      end

      context 'when ssl is enabled' do
        let(:ssl) { true }

        it 'creates an agent exporter that reports over https' do
          expect(described_class)
            .to receive(:_native_create_agent_exporter)
            .with('https://192.168.0.1:12345/', tags_as_array)
            .and_return([:ok, :dummy_exporter])

          http_transport
        end
      end

      context 'when agent_settings requests a unix domain socket' do
        let(:adapter) { Datadog::Transport::Ext::UnixSocket::ADAPTER }
        let(:uds_path) { '/var/run/datadog/apm.socket' }

        it 'creates an agent exporter that reports over a unix domain socket' do
          expect(described_class)
            .to receive(:_native_create_agent_exporter)
            .with('unix:///var/run/datadog/apm.socket', tags_as_array)
            .and_return([:ok, :dummy_exporter])

          http_transport
        end
      end

      context 'when agent_settings includes a deprecated_for_removal_transport_configuration_proc' do
        let(:deprecated_for_removal_transport_configuration_proc) { instance_double(Proc, 'Configuration proc') }

        it do
          expect { http_transport }.to raise_error(ArgumentError, /c.tracer.transport_options is currently unsupported/)
        end
      end

      context 'when agent_settings requests an unsupported transport' do
        let(:adapter) { :test }

        it do
          expect { http_transport }.to raise_error(ArgumentError, /Unsupported transport/)
        end
      end
    end

    context 'when additionally site and api_key are provided' do
      let(:site) { 'test.datadoghq.com' }
      let(:api_key) { SecureRandom.uuid }

      it 'ignores them and creates an agent exporter using the agent_settings' do
        expect(described_class)
          .to receive(:_native_create_agent_exporter)
          .with('http://192.168.0.1:12345/', tags_as_array)
          .and_return([:ok, :dummy_exporter])

        http_transport
      end

      context 'when agentless mode is allowed' do
        around do |example|
          ClimateControl.modify('DD_PROFILING_AGENTLESS' => 'true') do
            example.run
          end
        end

        it 'creates an agentless exporter with the given site and api key' do
          expect(described_class)
            .to receive(:_native_create_agentless_exporter)
            .with(site, api_key, tags_as_array)
            .and_return([:ok, :dummy_exporter])

          http_transport
        end
      end
    end

    context 'when an invalid configuration is provided' do
      let(:port) { 1_000_000_000.to_s }

      it do
        expect { http_transport }.to raise_error(ArgumentError, /Failed to initialize transport/)
      end
    end
  end

  describe '#export' do
    subject(:export) { http_transport.export(flush) }

    it 'calls the native export method with the data from the flush' do
      # Manually converted from the lets above :)
      upload_timeout_milliseconds = 123_000
      start_timespec_seconds = 1644249593
      start_timespec_nanoseconds = 987654321
      finish_timespec_seconds = 1699718400
      finish_timespec_nanoseconds = 123456789

      expect(described_class).to receive(:_native_do_export).with(
        kind_of(Datadog::Profiling::HttpTransport::Exporter),
        upload_timeout_milliseconds,
        start_timespec_seconds,
        start_timespec_nanoseconds,
        finish_timespec_seconds,
        finish_timespec_nanoseconds,
        pprof_file_name,
        pprof_data,
        code_provenance_file_name,
        code_provenance_data
      ).and_return([:ok, 200])

      export
    end

    context 'when export was successful' do
      before do
        expect(described_class).to receive(:_native_do_export).and_return([:ok, 200])
      end

      it 'logs a debug message' do
        expect(Datadog.logger).to receive(:debug).with('Successfully reported profiling data')

        export
      end

      it { is_expected.to be true }
    end

    context 'when failed' do
      before do
        expect(described_class).to receive(:_native_do_export).and_return([:ok, 500])
        allow(Datadog.logger).to receive(:error)
      end

      it 'logs an error message' do
        expect(Datadog.logger).to receive(:error)

        export
      end

      it { is_expected.to be false }
    end
  end

  context 'integration testing' do
    shared_context 'HTTP server' do
      let(:server) do
        WEBrick::HTTPServer.new(
          Port: port,
          Logger: log,
          AccessLog: access_log,
          StartCallback: -> { init_signal.push(1) }
        )
      end
      let(:hostname) { '127.0.0.1' }
      let(:port) { 6006 }
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

    include_context 'HTTP server'

    let(:request) { messages.first }

    let(:hostname) { '127.0.0.1' }
    let(:port) { '6006' }

    shared_examples 'correctly reports profiling data' do
      it 'correctly reports profiling data' do
        success = http_transport.export(flush)

        expect(success).to be true

        expect(request.header).to include(
          'content-type' => [%r{^multipart/form-data; boundary=(.+)}],
        )

        # check body
        boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)

        expect(body).to include(
          'version' => '3',
          'family' => 'ruby',
          'start' => start_timestamp,
          'end' => end_timestamp,
          "data[#{pprof_file_name}]" => pprof_data,
          "data[#{code_provenance_file_name}]" => code_provenance_data,
        )

        tags = body['tags[]'].list
        expect(tags).to include('tag_a:value_a', 'tag_b:value_b')
      end
    end

    include_examples 'correctly reports profiling data'

    it 'exports data via http to the agent url' do
      http_transport.export(flush)

      expect(request.request_uri.to_s).to eq 'http://127.0.0.1:6006/profiling/v1/input'
    end

    context 'via unix domain socket' do
      before { pending 'Support for reporting via unix domain socket in libddprof is still work in progress' }

      let(:temporary_directory) { Dir.mktmpdir }
      let(:socket_path) { "#{temporary_directory}/rspec_unix_domain_socket" }
      let(:unix_domain_socket) { UNIXServer.new(socket_path) } # Closing the socket is handled by webrick
      let(:server) do
        server = WEBrick::HTTPServer.new(
          DoNotListen: true,
          Logger: log,
          AccessLog: access_log,
          StartCallback: -> { init_signal.push(1) }
        )
        server.listeners << unix_domain_socket
        server
      end
      let(:adapter) { Datadog::Transport::Ext::UnixSocket::ADAPTER }
      let(:uds_path) { socket_path }

      after do
        begin
          FileUtils.remove_entry(temporary_directory)
        rescue Errno::ENOENT => _e
          # Do nothing, it's ok
        end
      end

      include_examples 'correctly reports profiling data'
    end

    context 'when agent is down' do
      before do
        server.shutdown
        @server_thread.join
      end

      it 'logs an error' do
        expect(Datadog.logger).to receive(:error).with(/error trying to connect/)

        http_transport.export(flush)
      end
    end

    context 'when request times out' do
      let(:upload_timeout_seconds) { 0.001 }
      let(:server_proc) { proc { sleep 0.05 } }

      it 'logs an error' do
        expect(Datadog.logger).to receive(:error).with(/timed out/)

        http_transport.export(flush)
      end
    end

    context 'when server returns a 4xx failure' do
      let(:server_proc) { proc { |_req, res| res.status = 418 } }

      it 'logs an error' do
        expect(Datadog.logger).to receive(:error).with(/unexpected HTTP 418/)

        http_transport.export(flush)
      end
    end

    context 'when server returns a 5xx failure' do
      let(:server_proc) { proc { |_req, res| res.status = 503 } }

      it 'logs an error' do
        expect(Datadog.logger).to receive(:error).with(/unexpected HTTP 503/)

        http_transport.export(flush)
      end
    end
  end
end
