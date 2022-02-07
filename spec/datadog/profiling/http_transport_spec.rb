# typed: false
require 'datadog/profiling/spec_helper'

require 'datadog/profiling'

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

  let(:agent_settings) { :FIXME }
  let(:site) { nil }
  let(:api_key) { nil }
  let(:tags) { :FIXME }
  let(:upload_timeout_seconds) { 123 }

  describe '#initialize' do
    context 'when agent_settings are provided' do
      it 'creates an agent exporter with the given settings'

      context 'when agent_settings request an unix domain socket' do
        it 'raises an ArgumentError'
      end

      context 'when agent_settings includes a transport_configuration_proc' do
        it 'raises an ArgumentError'
      end
    end

    context 'when site and api_key are provided' do
      it 'creates an agent exporter with the given settings'

      context 'when agentless mode is allowed' do
        it 'creates an agentless exporter with the given site and api key'
      end
    end
  end

  describe '#export' do
    let(:flush) { :FIXME }

    it 'calls the native export method with the data from the flush'

    context 'integration testing' do
      it 'reports the data successfully'
    end
  end
end
