require 'datadog/profiling/spec_helper'

require 'datadog/profiling/http_transport'
require 'datadog/profiling'

require 'json'
require 'socket'
require 'webrick'

# Design note for this class's specs: from the Ruby code side, we're treating the `_native_` methods as an API
# between the Ruby code and the native methods, and thus in this class we have a bunch of tests to make sure the
# native methods are invoked correctly.
#
# We also have "integration" specs, where we exercise the Ruby code together with the C code and libdatadog to ensure
# that things come out of libdatadog as we expected.
RSpec.describe Datadog::Profiling::HttpTransport do
  before { skip_if_profiling_not_supported(self) }

  subject(:http_transport) do
    described_class.new(
      agent_settings: agent_settings,
      site: site,
      api_key: api_key,
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
  let(:upload_timeout_seconds) { 10 }

  let(:flush) do
    Datadog::Profiling::Flush.new(
      start: start,
      finish: finish,
      pprof_file_name: pprof_file_name,
      pprof_data: pprof_data,
      code_provenance_file_name: code_provenance_file_name,
      code_provenance_data: code_provenance_data,
      tags_as_array: tags_as_array,
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
  let(:tags_as_array) { [%w[tag_a value_a], %w[tag_b value_b]] }

  describe '#initialize' do
    context 'when agent_settings are provided' do
      it 'picks the :agent working mode for the exporter' do
        expect(described_class)
          .to receive(:_native_validate_exporter)
          .with([:agent, 'http://192.168.0.1:12345/'])
          .and_return([:ok, nil])

        http_transport
      end

      context 'when ssl is enabled' do
        let(:ssl) { true }

        it 'picks the :agent working mode with https reporting' do
          expect(described_class)
            .to receive(:_native_validate_exporter)
            .with([:agent, 'https://192.168.0.1:12345/'])
            .and_return([:ok, nil])

          http_transport
        end
      end

      context 'when agent_settings requests a unix domain socket' do
        let(:adapter) { Datadog::Transport::Ext::UnixSocket::ADAPTER }
        let(:uds_path) { '/var/run/datadog/apm.socket' }

        it 'picks the :agent working mode with unix domain stocket reporting' do
          expect(described_class)
            .to receive(:_native_validate_exporter)
            .with([:agent, 'unix:///var/run/datadog/apm.socket'])
            .and_return([:ok, nil])

          http_transport
        end
      end

      context 'when agent_settings includes a deprecated_for_removal_transport_configuration_proc' do
        let(:deprecated_for_removal_transport_configuration_proc) { instance_double(Proc, 'Configuration proc') }

        it 'logs a warning message' do
          expect(Datadog.logger).to receive(:warn)

          http_transport
        end

        it 'picks working mode from the agent_settings object' do
          allow(Datadog.logger).to receive(:warn)

          expect(described_class)
            .to receive(:_native_validate_exporter)
            .with([:agent, 'http://192.168.0.1:12345/'])
            .and_return([:ok, nil])

          http_transport
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

      it 'ignores them and picks the :agent working mode using the agent_settings' do
        expect(described_class)
          .to receive(:_native_validate_exporter)
          .with([:agent, 'http://192.168.0.1:12345/'])
          .and_return([:ok, nil])

        http_transport
      end

      context 'when agentless mode is allowed' do
        around do |example|
          ClimateControl.modify('DD_PROFILING_AGENTLESS' => 'true') do
            example.run
          end
        end

        it 'picks the :agentless working mode with the given site and api key' do
          expect(described_class)
            .to receive(:_native_validate_exporter)
            .with([:agentless, site, api_key])
            .and_return([:ok, nil])

          http_transport
        end
      end
    end

    context 'when an invalid configuration is provided' do
      let(:hostname) { 'this:is:not:a:valid:hostname!!!!' }

      it do
        expect { http_transport }.to raise_error(ArgumentError, /Failed to initialize transport/)
      end
    end
  end

  describe '#export' do
    subject(:export) { http_transport.export(flush) }

    it 'calls the native export method with the data from the flush' do
      # Manually converted from the lets above :)
      upload_timeout_milliseconds = 10_000
      start_timespec_seconds = 1644249593
      start_timespec_nanoseconds = 987654321
      finish_timespec_seconds = 1699718400
      finish_timespec_nanoseconds = 123456789

      expect(described_class).to receive(:_native_do_export).with(
        kind_of(Array), # exporter_configuration
        upload_timeout_milliseconds,
        start_timespec_seconds,
        start_timespec_nanoseconds,
        finish_timespec_seconds,
        finish_timespec_nanoseconds,
        pprof_file_name,
        pprof_data,
        code_provenance_file_name,
        code_provenance_data,
        tags_as_array
      ).and_return([:ok, 200])

      export
    end

    context 'when successful' do
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
      let(:log) { WEBrick::Log.new($stderr, WEBrick::Log::WARN) }
      let(:access_log_buffer) { StringIO.new }
      let(:access_log) { [[access_log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
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
          'dd-evp-origin' => ['dd-trace-rb'],
          'dd-evp-origin-version' => [DDTrace::VERSION::STRING],
        )

        # check body
        boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)
        event_data = JSON.parse(body.fetch('event'))

        expect(event_data).to eq(
          'attachments' => [pprof_file_name, code_provenance_file_name],
          'tags_profiler' => 'tag_a:value_a,tag_b:value_b',
          'start' => start_timestamp,
          'end' => end_timestamp,
          'family' => 'ruby',
          'version' => '4',
          'endpoint_counts' => nil,
        )
      end

      it 'reports the payload as lz4-compressed files, that get automatically compressed by libdatadog' do
        success = http_transport.export(flush)

        expect(success).to be true

        boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)

        require 'extlz4' # Lazily required, to avoid trying to load it on JRuby

        expect(LZ4.decode(body.fetch(pprof_file_name))).to eq pprof_data
        expect(LZ4.decode(body.fetch(code_provenance_file_name))).to eq code_provenance_data
      end
    end

    include_examples 'correctly reports profiling data'

    it 'exports data via http to the agent url' do
      http_transport.export(flush)

      expect(request.request_uri.to_s).to eq 'http://127.0.0.1:6006/profiling/v1/input'
    end

    context 'when code provenance data is not available' do
      let(:code_provenance_data) { nil }

      it 'correctly reports profiling data but does not include code provenance' do
        success = http_transport.export(flush)

        expect(success).to be true

        # check body
        boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)
        event_data = JSON.parse(body.fetch('event'))

        expect(event_data).to eq(
          'attachments' => [pprof_file_name],
          'tags_profiler' => 'tag_a:value_a,tag_b:value_b',
          'start' => start_timestamp,
          'end' => end_timestamp,
          'family' => 'ruby',
          'version' => '4',
          'endpoint_counts' => nil,
        )

        expect(body[code_provenance_file_name]).to be nil
      end
    end

    context 'via unix domain socket' do
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

    context 'when tags contains invalid tags' do
      let(:tags_as_array) { [%w[:invalid invalid:], %w[valid1 valid1], %w[valid2 valid2]] }

      before do
        allow(Datadog.logger).to receive(:warn)
      end

      it 'reports using the valid tags and ignores the invalid tags' do
        success = http_transport.export(flush)

        expect(success).to be true

        boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
        body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)
        event_data = JSON.parse(body.fetch('event'))

        expect(event_data['tags_profiler']).to eq 'valid1:valid1,valid2:valid2'
      end

      it 'logs a warning' do
        expect(Datadog.logger).to receive(:warn).with(/Failed to add tag to profiling request/)

        http_transport.export(flush)
      end
    end

    describe 'cancellation behavior' do
      let!(:request_received_queue) { Queue.new }
      let!(:request_finish_queue) { Queue.new }

      let(:upload_timeout_seconds) { 123_456_789 } # Set on purpose so this test will either pass or hang
      let(:server_proc) do
        proc do
          request_received_queue << true
          request_finish_queue.pop
        end
      end

      after do
        request_finish_queue << true
      end

      # As the describe above says, here we're testing the cancellation behavior. If cancellation is not correctly
      # implemented, then `ddog_ProfileExporter_send` will block until `upload_timeout_seconds` is hit and
      # nothing we could do on the Ruby VM side will interrupt it.
      # If it is correctly implemented, then the `exporter_thread.kill` will cause
      # `ddog_ProfileExporter_send` to return immediately and this test will quickly finish.
      it 'can be interrupted' do
        exporter_thread = Thread.new { http_transport.export(flush) }
        request_received_queue.pop

        expect(exporter_thread.status).to eq 'sleep'

        exporter_thread.kill
        exporter_thread.join

        expect(exporter_thread.status).to be false
      end
    end
  end
end
