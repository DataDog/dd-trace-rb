# frozen_string_literal: true

require 'ostruct'

require 'spec_helper'

require 'ostruct'
require 'datadog/core/utils/base64'
require 'datadog/core/remote/transport/http'
require 'datadog/core/remote/transport/http/negotiation'
require 'datadog/core/remote/transport/negotiation'

RSpec.describe Datadog::Core::Remote::Transport::HTTP do
  shared_context 'HTTP connection stub' do
    before do
      request_class = case request_verb
                      when :get then ::Net::HTTP::Get
                      when :post then ::Net::HTTP::Post
                      else raise "bad verb: #{request_verb.inspect}"
                      end
      http_request = instance_double(request_class)
      allow(http_request).to receive(:body=)
      allow(request_class).to receive(:new).and_return(http_request)

      allow(::Net::HTTP).to receive(:new).and_return(http_connection)

      allow(http_connection).to receive(:open_timeout=)
      allow(http_connection).to receive(:read_timeout=)
      allow(http_connection).to receive(:use_ssl=)

      allow(http_connection).to receive(:start).and_yield(http_connection)

      http_response = instance_double(::Net::HTTPResponse, body: response_body, code: response_code)
      allow(http_connection).to receive(:request).with(http_request).and_return(http_response)
    end
  end

  let(:http_connection) { instance_double(::Net::HTTP) }

  describe '.root' do
    subject(:transport) { described_class.root(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Core::Remote::Transport::Negotiation::Transport) }

    describe '#send_info' do
      include_context 'HTTP connection stub'

      subject(:response) { transport.send_info }

      let(:request_verb) { :get }

      let(:response_code) { 200 }
      let(:response_body) do
        JSON.dump(
          {
            version: '42',
            endpoints: [
              '/info',
              '/v0/path',
            ],
            config: {
              max_request_bytes: '1234',
            }
          }
        )
      end

      it { is_expected.to be_a(Datadog::Core::Remote::Transport::HTTP::Negotiation::Response) }

      it { is_expected.to be_ok }
      it { is_expected.to have_attributes(:version => '42') }
      it { is_expected.to have_attributes(:endpoints => ['/info', '/v0/path']) }
      it { is_expected.to have_attributes(:config => { max_request_bytes: '1234' }) }

      it { expect(transport.client.api.headers).to_not include('Datadog-Client-Computed-Stats') }

      context 'with ASM standalone enabled' do
        before { expect(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(true) }

        it { expect(transport.client.api.headers['Datadog-Client-Computed-Stats']).to eq('yes') }
      end
    end
  end

  describe '.v7' do
    subject(:transport) { described_class.v7(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Core::Remote::Transport::Config::Transport) }

    describe '#send_config' do
      include_context 'HTTP connection stub'

      let(:state) do
        OpenStruct.new(
          {
            root_version: 1,              # unverified mode, so 1
            targets_version: 0,           # from scratch, so zero
            config_states: [],            # from scratch, so empty
            has_error: false,             # from scratch, so false
            error: '',                    # from scratch, so blank
            opaque_backend_state: '',     # from scratch, so blank
          }
        )
      end

      let(:id) { SecureRandom.uuid }

      let(:products) { [] }

      let(:capabilities) { 0 }

      let(:capabilities_binary) do
        capabilities
          .to_s(16)
          .tap { |s| s.size.odd? && s.prepend('0') }
          .scan(/\h\h/)
          .map { |e| e.to_i(16) }
          .pack('C*')
      end

      let(:payload) do
        {
          client: {
            state: {
              root_version: state.root_version,
              targets_version: state.targets_version,
              config_states: state.config_states,
              has_error: state.has_error,
              error: state.error,
              backend_client_state: state.opaque_backend_state,
            },
            id: id,
            products: products,
            is_tracer: true,
            is_agent: false,
            client_tracer: {
              runtime_id: Datadog::Core::Environment::Identity.id,
              language: Datadog::Core::Environment::Identity.lang,
              tracer_version: Datadog::Core::Environment::Identity.gem_datadog_version,
              service: Datadog.configuration.service,
              env: Datadog.configuration.env,
              tags: [],
            },
            capabilities: Datadog::Core::Utils::Base64.encode64(capabilities_binary).chomp,
          },
          cached_target_files: [],
        }
      end

      let(:request_verb) { :post }

      let(:response_code) { 200 }
      let(:response_body) do
        encode = proc do |obj|
          Datadog::Core::Utils::Base64.strict_encode64(obj).chomp
        end

        jencode = proc do |obj|
          Datadog::Core::Utils::Base64.strict_encode64(JSON.dump(obj)).chomp
        end

        JSON.dump(
          {
            roots: [
              jencode.call({}),
              jencode.call({}),
            ],
            targets: jencode.call(
              {
                signed: {
                  expires: '2022-09-22T09:01:04Z',
                  targets: {
                    'datadog/42/PRODUCT/foo/config' => {
                      hashes: { sha256: 'd0b425e00e15a0d36b9b361f02bab63563aed6cb4665083905386c55d5b679fa' },
                      length: 8,
                    },
                    'employee/PRODUCT/bar/config' => {
                      hashes: { sha256: 'dab741b6289e7dccc1ed42330cae1accc2b755ce8079c2cd5d4b5366c9f769a6' },
                      length: 8,
                    },
                  }
                }
              }
            ),
            target_files: [
              {
                path: 'datadog/42/PRODUCT/foo/config',
                raw: encode.call('content1'),
              },
              {
                path: 'employee/PRODUCT/bar/config',
                raw: encode.call('content2'),
              },
            ],
            client_configs: [
              'datadog/42/PRODUCT/foo/config',
              'employee/PRODUCT/bar/config',
            ],
          }
        )
      end

      subject(:response) { transport.send_config(payload) }

      it { is_expected.to be_a(Datadog::Core::Remote::Transport::HTTP::Config::Response) }

      it { is_expected.to be_ok }
      it { is_expected.to have_attributes(:roots => be_a(Array)) }
      it { is_expected.to have_attributes(:targets => be_a(Hash)) }
      it { is_expected.to have_attributes(:target_files => be_a(Array)) }

      it { expect(transport.client.api.headers).to_not include('Datadog-Client-Computed-Stats') }

      context 'with ASM standalone enabled' do
        before { expect(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(true) }

        it { expect(transport.client.api.headers['Datadog-Client-Computed-Stats']).to eq('yes') }
      end

      context 'with a network error' do
        it 'raises a transport error' do
          expect(http_connection).to receive(:request).and_raise(IOError)

          expect(Datadog.logger).to receive(:debug).with(/IOError/)

          expect(response).to have_attributes(internal_error?: true)
        end
      end
    end
  end
end
