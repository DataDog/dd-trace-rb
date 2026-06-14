# frozen_string_literal: true

require 'spec_helper'

require 'datadog/tracing/transport/otlp/exporter'

RSpec.describe Datadog::Tracing::Transport::OTLP::Exporter, webmock: true do
  subject(:exporter) do
    described_class.new(
      endpoint: endpoint,
      headers: headers,
      timeout_millis: timeout_millis,
      logger: logger
    )
  end

  let(:endpoint) { 'http://collector.test:4318/v1/traces' }
  let(:headers) { {'api-key' => 'secret'} }
  let(:timeout_millis) { 5000 }
  let(:logger) { logger_allowing_debug }
  let(:payload) { '{"resourceSpans":[]}' }

  describe '#initialize' do
    it 'parses the endpoint and converts the timeout to seconds' do
      expect(exporter.uri.to_s).to eq(endpoint)
      expect(exporter.timeout_seconds).to eq(5.0)
    end
  end

  describe '#export' do
    subject(:export) { exporter.export(payload) }

    context 'when the collector responds 200' do
      let!(:stub) do
        stub_request(:post, endpoint).to_return(status: 200)
      end

      it 'sends the payload with the JSON content type and configured headers' do
        expect(export).to be(true)
        expect(stub).to have_been_requested
        expect(
          a_request(:post, endpoint).with(
            body: payload,
            headers: {'Content-Type' => 'application/json', 'api-key' => 'secret'}
          )
        ).to have_been_made
      end

      it 'marks the request as internal/untraced' do
        export
        expect(
          a_request(:post, endpoint).with(headers: {'DD-Internal-Untraced-Request' => '1'})
        ).to have_been_made
      end
    end

    context 'when the collector responds with an error status' do
      before { stub_request(:post, endpoint).to_return(status: 500, body: 'nope') }

      it 'returns false without raising' do
        expect(export).to be(false)
      end
    end

    context 'when the request raises' do
      before { stub_request(:post, endpoint).to_raise(Errno::ECONNREFUSED) }

      it 'returns false without raising' do
        expect(export).to be(false)
      end
    end

    context 'with an https endpoint' do
      let(:endpoint) { 'https://collector.test:4318/v1/traces' }

      before { stub_request(:post, endpoint).to_return(status: 200) }

      it 'enables SSL' do
        expect(export).to be(true)
        expect(a_request(:post, endpoint)).to have_been_made
      end
    end
  end
end
