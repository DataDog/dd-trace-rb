require 'spec_helper'

require 'datadog/tracing/transport/http/traces'

RSpec.describe Datadog::Tracing::Transport::HTTP::Traces::Response do
  subject(:response) { described_class.new(http_response, options) }

  let(:http_response) { instance_double(Datadog::Core::Transport::Response) }
  let(:options) { {} }

  it { is_expected.to be_a_kind_of(Datadog::Core::Transport::HTTP::Response) }
  it { is_expected.to be_a_kind_of(Datadog::Tracing::Transport::Traces::Response) }

  describe '#initialize' do
    it { is_expected.to have_attributes(service_rates: nil) }

    context 'given a \'service_rates\' option' do
      let(:options) { {service_rates: service_rates} }
      let(:service_rates) { instance_double(Hash) }

      it { is_expected.to have_attributes(service_rates: service_rates) }
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::HTTP::Client do
  let(:logger) { logger_allowing_debug }
  let(:api) { double(Datadog::Core::Transport::HTTP::API::Instance, endpoint: endpoint) }
  let(:endpoint) { double(Datadog::Core::Transport::HTTP::API::Endpoint) }

  subject(:client) { described_class.new(api, logger: logger) }

  describe '#send_request' do
    subject(:send_request_traces) { client.send_request(:traces, request) }

    let(:request) { instance_double(Datadog::Tracing::Transport::Traces::Request) }
    let(:response) { instance_double(Datadog::Tracing::Transport::HTTP::Traces::Response) }

    before do
      expect(client).to receive(:update_stats_from_response!)
        .with(response)

      expect(endpoint).to receive(:call) do |env|
        expect(env).to be_a_kind_of(Datadog::Core::Transport::HTTP::Env)
        expect(env.request).to be(request)
        response
      end
    end

    it { is_expected.to eq(response) }
  end
end

RSpec.describe Datadog::Tracing::Transport::HTTP::Traces::API::Endpoint do
  subject(:endpoint) { described_class.new(path, encoder, options) }

  let(:path) { double('path') }
  let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder, content_type: content_type) }
  let(:content_type) { 'application/test-type' }
  let(:options) { {} }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        verb: :post,
        path: path,
        encoder: encoder,
        service_rates?: false
      )
    end
  end

  describe '#service_rates?' do
    subject(:service_rates?) { endpoint.service_rates? }

    it { is_expected.to be false }

    context 'when initialized with a \'service_rates\' option' do
      let(:options) { {service_rates: true} }

      it { is_expected.to be true }
    end
  end

  describe '#call' do
    subject(:call) { endpoint.call(env, &block) }

    let(:env) { Datadog::Core::Transport::HTTP::Env.new(request) }
    let(:request) { Datadog::Tracing::Transport::Traces::Request.new(parcel) }
    let(:parcel) { double(Datadog::Tracing::Transport::Traces::EncodedParcel, data: data, trace_count: trace_count) }
    let(:data) { double('trace_once') }
    let(:trace_count) { 123 }

    let(:handler) { spy('handler') }
    let(:http_response) { instance_double(Datadog::Tracing::Transport::HTTP::Traces::Response, trace_count: trace_count) }

    let(:block) do
      proc do |env|
        handler.verb(env.verb)
        handler.path(env.path)
        handler.body(env.body)
        handler.headers(env.headers)
        handler.http_response
      end
    end

    before do
      allow(handler).to receive(:http_response).and_return(http_response)
    end

    shared_examples_for 'traces request' do
      it 'has correct attributes' do
        is_expected.to be_a(Datadog::Tracing::Transport::HTTP::Traces::Response)
        expect(handler).to have_received(:verb).with(:post)
        expect(handler).to have_received(:path).with(path)
        expect(handler).to have_received(:body).with(data)
        expect(handler).to have_received(:headers).with(
          described_class::HEADER_CONTENT_TYPE => content_type,
          described_class::HEADER_TRACE_COUNT => trace_count.to_s
        )
      end
    end

    it 'response has trace count' do
      expect(call.trace_count).to eq(trace_count)
    end

    context 'when service_rates? is false' do
      let(:options) { {service_rates: false} }

      it_behaves_like 'traces request'
    end

    context 'when service_rates? is true' do
      let(:options) { {service_rates: true} }

      # Build and return a JSON payload
      let(:json_payload) { sampling_response.to_json }
      let(:sampling_response) { {described_class::SERVICE_RATE_KEY => service_rates} }
      let(:service_rates) { {'service:a,env:test' => 0.1, 'service:b,env:test' => 0.5} }

      before { allow(http_response).to receive(:payload).and_return(json_payload) }

      it_behaves_like 'traces request'
      it 'includes service rates' do
        expect(call.service_rates).to eq(service_rates)
      end
    end
  end
end
