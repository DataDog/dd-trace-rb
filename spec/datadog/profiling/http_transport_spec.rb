# typed: false
require 'datadog/profiling/spec_helper'

require 'datadog/profiling/http_transport'
require 'datadog/profiling'

# Design note for this class's specs: from the Ruby code side, we're treating the `_native_` methods as an API
# between the Ruby code and the native methods, and thus in this class we have a bunch of tests to make sure the
# native methods are invoked correctly.
#
# We also have a few integration tests, where we also exercise libddprof and ensure that things come out of libddprof
# as we expect.
RSpec.describe Datadog::Profiling::HttpTransport do
  #before { skip_if_profiling_not_supported(self) }

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
    instance_double(
      Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings,
      adapter: adapter,
      ssl: ssl,
      hostname: '192.168.0.1',
      port: '12345',
      deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc,
    )
  end
  let(:adapter) { Datadog::Transport::Ext::HTTP::ADAPTER }
  let(:ssl) { false }
  let(:deprecated_for_removal_transport_configuration_proc) { nil }
  let(:site) { nil }
  let(:api_key) { nil }
  let(:tags) { :FIXME }
  let(:upload_timeout_seconds) { 123 }

  describe '#initialize' do
    context 'when agent_settings are provided' do
      it 'creates an agent exporter with the given settings' do
        expect(described_class)
          .to receive(:_native_create_agent_exporter).with('http://192.168.0.1:12345/', tags)

        http_transport
      end

      context 'when ssl is enabled' do
        let(:ssl) { true }

        it 'creates an agent exporter that reports over https' do
          expect(described_class)
            .to receive(:_native_create_agent_exporter).with('https://192.168.0.1:12345/', tags)

          http_transport
        end
      end

      context 'when agent_settings requests an unix domain socket' do
        let(:adapter) { Datadog::Transport::Ext::UnixSocket::ADAPTER }

        it do
          expect { http_transport }.to raise_error(ArgumentError, /Unix Domain Sockets are currently unsupported/)
        end
      end

      context 'when agent_settings includes a deprecated_for_removal_transport_configuration_proc' do
        let(:deprecated_for_removal_transport_configuration_proc) { instance_double(Proc, 'Configuration proc') }

        it do
          expect { http_transport }.to raise_error(ArgumentError, /c.tracer.transport_options is currently unsupported/)
        end
      end
    end

    context 'when additionally site and api_key are provided' do
      let(:site) { 'test.datadoghq.com' }
      let(:api_key) { SecureRandom.uuid }

      it 'ignores them and creates an agent exporter using the agent_settings' do
        expect(described_class)
          .to receive(:_native_create_agent_exporter).with('http://192.168.0.1:12345/', tags)

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
            .to receive(:_native_create_agentless_exporter).with(site, api_key, tags)

          http_transport
        end
      end
    end
  end

  describe '#export' do
    subject(:export) { http_transport.export(flush) }

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
    let(:start)  { Time.iso8601("2022-02-07T15:59:53.987654321Z") }
    let(:finish) { Time.iso8601("2023-11-11T16:00:00.123456789Z") }
    let(:pprof_file_name) { 'the_pprof_file_name.pprof' }
    let(:pprof_data) { 'the_pprof_data' }
    let(:code_provenance_file_name) { 'the_code_provenance_file_name.json' }
    let(:code_provenance_data) { 'the_code_provenance_data' }

    it 'calls the native export method with the data from the flush' do
      # Manually converted from the lets above :)
      upload_timeout_milliseconds = 123_000
      start_timespec_seconds = 1644249593
      start_timespec_nanoseconds = 987654321
      finish_timespec_seconds = 1699718400
      finish_timespec_nanoseconds = 123456789

      expect(described_class).to receive(:_native_do_export).with(
        anything, # libddprof_exporter
        upload_timeout_milliseconds,
        start_timespec_seconds,
        start_timespec_nanoseconds,
        finish_timespec_seconds,
        finish_timespec_nanoseconds,
        pprof_file_name,
        pprof_data,
        code_provenance_file_name,
        code_provenance_data
      )

      export
    end
  end

  context 'integration testing' do
    context 'when in agentless mode' do
      it 'can export data successfully'
    end

    context 'when in agent mode' do
      it 'can export data successfully'
    end
  end
end
