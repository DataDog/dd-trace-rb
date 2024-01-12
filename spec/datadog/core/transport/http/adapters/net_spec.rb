require 'spec_helper'

require 'datadog/core/transport/http/adapters/net'
require 'datadog/core/configuration/agent_settings_resolver'

RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Net do
  subject(:adapter) { described_class.new(agent_settings) }

  let(:hostname) { 'hostname' }
  let(:port) { 9999 }
  let(:timeout) { 15 }
  let(:ssl) { false }
  let(:proxy_addr) { nil } # We currently disable proxy for transport HTTP requests
  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
      adapter: nil,
      ssl: ssl,
      uds_path: nil,
      hostname: hostname,
      port: port,
      timeout_seconds: timeout,
    )
  end

  shared_context 'HTTP connection stub' do
    let(:http_connection) { instance_double(::Net::HTTP) }

    before do
      allow(::Net::HTTP).to receive(:new)
        .with(
          adapter.hostname,
          adapter.port,
          proxy_addr
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
        Datadog::Core::Transport::HTTP::Env,
        path: path,
        body: body,
        headers: headers,
        form: form
      )
    end

    let(:path) { '/foo' }
    let(:body) { '{}' }
    let(:headers) { {} }
    let(:form) { {} }
  end

  describe '#initialize' do
    context 'given a :timeout option' do
      let(:timeout) { double('timeout') }

      it { is_expected.to have_attributes(timeout: timeout) }
    end

    context 'given a :ssl option' do
      context 'with true' do
        let(:ssl) { true }

        it { is_expected.to have_attributes(ssl: true) }
      end
    end
  end

  describe '#open' do
    include_context 'HTTP connection stub'

    it 'opens and yields a Net::HTTP connection' do
      expect { |b| adapter.open(&b) }.to yield_with_args(http_connection)
    end
  end

  describe '#call' do
    include_context 'HTTP Env'

    subject(:call) { adapter.call(env) }

    context 'given an HTTP::Env with a verb' do
      before { allow(env).to receive(:verb).and_return(verb) }

      context ':get' do
        include_context 'HTTP connection stub'
        let(:verb) { :get }
        let(:http_response) { double('http_response') }

        context 'and a simple get request' do
          let(:get) { instance_double(Net::HTTP::Get) }

          it 'makes a GET and produces a response' do
            expect(Net::HTTP::Get)
              .to receive(:new)
              .with(env.path, env.headers)
              .and_return(get)

            expect(http_connection)
              .to receive(:request)
              .with(get)
              .and_return(http_response)

            is_expected.to be_a_kind_of(described_class::Response)
            expect(call.http_response).to be(http_response)
          end
        end
      end

      context ':post' do
        include_context 'HTTP connection stub'
        let(:verb) { :post }
        let(:http_response) { double('http_response') }

        context 'and an empty form body' do
          let(:form) { {} }
          let(:post) { instance_double(Net::HTTP::Post) }

          it 'makes a POST and produces a response' do
            expect(Net::HTTP::Post)
              .to receive(:new)
              .with(env.path, env.headers)
              .and_return(post)

            expect(post)
              .to receive(:body=)
              .with(env.body)

            expect(http_connection)
              .to receive(:request)
              .with(post)
              .and_return(http_response)

            is_expected.to be_a_kind_of(described_class::Response)
            expect(call.http_response).to be(http_response)
          end
        end

        context 'and a form with fields' do
          let(:form) { { 'id' => '1234', 'type' => 'Test' } }
          let(:multipart_post) { instance_double(Datadog::Core::Vendor::Net::HTTP::Post::Multipart) }

          it 'makes a multipart POST and produces a response' do
            expect(Datadog::Core::Vendor::Net::HTTP::Post::Multipart)
              .to receive(:new)
              .with(env.path, env.form, env.headers)
              .and_return(multipart_post)

            expect(http_connection)
              .to receive(:request)
              .with(multipart_post)
              .and_return(http_response)

            is_expected.to be_a_kind_of(described_class::Response)
            expect(call.http_response).to be(http_response)
          end
        end
      end

      context ':head' do
        let(:verb) { :head }

        it { expect { call }.to raise_error(described_class::UnknownHTTPMethod) }
      end

      context ':put' do
        let(:verb) { :put }

        it { expect { call }.to raise_error(described_class::UnknownHTTPMethod) }
      end

      context ':delete' do
        let(:verb) { :delete }

        it { expect { call }.to raise_error(described_class::UnknownHTTPMethod) }
      end

      context ':patch' do
        let(:verb) { :patch }

        it { expect { call }.to raise_error(described_class::UnknownHTTPMethod) }
      end
    end
  end

  describe '#post' do
    include_context 'HTTP connection stub'
    include_context 'HTTP Env'

    subject(:post) { adapter.post(env) }

    let(:http_response) { double('http_response') }

    before { expect(http_connection).to receive(:request).and_return(http_response) }

    it 'produces a response' do
      is_expected.to be_a_kind_of(described_class::Response)
      expect(post.http_response).to be(http_response)
    end
  end

  describe '#url' do
    subject(:url) { adapter.url }

    let(:hostname) { 'local.test' }
    let(:port) { '345' }
    let(:timeout) { 7 }

    it { is_expected.to eq('http://local.test:345?timeout=7') }
  end
end

RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Net::Response do
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

    context 'when code is 199' do
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

    context 'when code is 300' do
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
