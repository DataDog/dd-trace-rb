require 'spec_helper'

require 'datadog/core/telemetry/http/adapters/net'

RSpec.describe Datadog::Core::Telemetry::Http::Adapters::Net do
  subject(:adapter) { described_class.new(hostname: hostname, port: port, **options) }

  let(:hostname) { double('hostname') }
  let(:port) { double('port') }
  let(:timeout) { double('timeout') }
  let(:options) { { timeout: timeout } }

  shared_context 'HTTP connection stub' do
    let(:http_connection) { instance_double(::Net::HTTP) }

    before do
      allow(::Net::HTTP).to receive(:new)
        .with(
          adapter.hostname,
          adapter.port,
        ).and_return(http_connection)

      allow(http_connection).to receive(:open_timeout=).with(adapter.timeout)
      allow(http_connection).to receive(:read_timeout=).with(adapter.timeout)
      allow(http_connection).to receive(:use_ssl=).with(adapter.ssl)

      allow(http_connection).to receive(:start).and_yield(http_connection)
    end
  end

  shared_context 'HTTP Env' do
    let(:env) do
      instance_double(
        Datadog::Core::Telemetry::Http::Env,
        path: path,
        body: body,
        headers: headers,
      )
    end

    let(:path) { '/foo' }
    let(:body) { '{}' }
    let(:headers) { {} }
  end

  describe '#initialize' do
    context 'given no options' do
      let(:options) { {} }

      it do
        is_expected.to have_attributes(
          hostname: hostname,
          port: port,
          timeout: Datadog::Core::Telemetry::Http::Adapters::Net::DEFAULT_TIMEOUT,
          ssl: true
        )
      end
    end

    context 'given a :timeout option' do
      let(:options) { { timeout: timeout } }
      let(:timeout) { double('timeout') }

      it { is_expected.to have_attributes(timeout: timeout) }
    end

    context 'given a :ssl option' do
      let(:options) { { ssl: ssl } }

      context 'with nil' do
        let(:ssl) { nil }

        it { is_expected.to have_attributes(ssl: true) }
      end

      context 'with false' do
        let(:ssl) { false }

        it { is_expected.to have_attributes(ssl: false) }
      end
    end
  end

  describe '#open' do
    include_context 'HTTP connection stub'

    it 'opens and yields a Net::HTTP connection' do
      expect { |b| adapter.open(&b) }.to yield_with_args(http_connection)
    end
  end

  describe '#post' do
    include_context 'HTTP connection stub'
    include_context 'HTTP Env'

    subject(:post) { adapter.post(env) }

    let(:http_response) { double('http_response') }

    context 'when request goes through' do
      before { expect(http_connection).to receive(:request).and_return(http_response) }

      it 'produces a response' do
        is_expected.to be_a_kind_of(described_class::Response)
        expect(post.http_response).to be(http_response)
      end
    end

    context 'when error in connecting to agent' do
      before { expect(http_connection).to receive(:request).and_raise(StandardError) }
      it { expect(post).to be_a_kind_of(Datadog::Core::Telemetry::Http::InternalErrorResponse) }
    end
  end
end

RSpec.describe Datadog::Core::Telemetry::Http::Adapters::Net::Response do
  subject(:response) { described_class.new(http_response) }

  let(:http_response) { instance_double(::Net::HTTPResponse) }

  describe '#initialize' do
    it { is_expected.to have_attributes(http_response: http_response) }
  end

  describe '#payload' do
    subject(:payload) { response.payload }

    let(:http_response) { instance_double(::Net::HTTPResponse, body: double('body')) }

    it { is_expected.to be(http_response.body) }
  end

  describe '#code' do
    subject(:code) { response.code }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: '200') }

    it { is_expected.to eq(200) }
  end

  describe '#ok?' do
    subject(:ok?) { response.ok? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code not 2xx' do
      let(:code) { 199 }

      it { is_expected.to be false }
    end

    context 'when code is 200' do
      let(:code) { 200 }

      it { is_expected.to be true }
    end

    context 'when code is 299' do
      let(:code) { 299 }

      it { is_expected.to be true }
    end

    context 'when code is greater than 299' do
      let(:code) { 300 }

      it { is_expected.to be false }
    end
  end

  describe '#unsupported?' do
    subject(:unsupported?) { response.unsupported? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 400' do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context 'when code is 415' do
      let(:code) { 415 }

      it { is_expected.to be true }
    end
  end

  describe '#not_found?' do
    subject(:not_found?) { response.not_found? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 400' do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context 'when code is 404' do
      let(:code) { 404 }

      it { is_expected.to be true }
    end
  end

  describe '#client_error?' do
    subject(:client_error?) { response.client_error? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 399' do
      let(:code) { 399 }

      it { is_expected.to be false }
    end

    context 'when code is 400' do
      let(:code) { 400 }

      it { is_expected.to be true }
    end

    context 'when code is 499' do
      let(:code) { 499 }

      it { is_expected.to be true }
    end

    context 'when code is 500' do
      let(:code) { 500 }

      it { is_expected.to be false }
    end
  end

  describe '#server_error?' do
    subject(:server_error?) { response.server_error? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 499' do
      let(:code) { 499 }

      it { is_expected.to be false }
    end

    context 'when code is 500' do
      let(:code) { 500 }

      it { is_expected.to be true }
    end

    context 'when code is 599' do
      let(:code) { 599 }

      it { is_expected.to be true }
    end

    context 'when code is 600' do
      let(:code) { 600 }

      it { is_expected.to be false }
    end
  end
end
