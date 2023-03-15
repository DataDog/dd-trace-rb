# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/transport/http'
require 'datadog/core/transport/http/negotiation'
require 'datadog/core/transport/negotiation'

RSpec.describe Datadog::Core::Transport::HTTP do
  describe '.root' do
    subject(:transport) { described_class.root(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Core::Transport::Negotiation::Transport) }

    describe '#send_info' do
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

      before do
        request_class = case request_verb
                        when :get then ::Net::HTTP::Get
                        else raise "bad verb: #{request_verb.inspect}"
                        end
        http_request = instance_double(request_class)
        allow(request_class).to receive(:new).and_return(http_request)

        http_connection = instance_double(::Net::HTTP)
        allow(::Net::HTTP).to receive(:new).and_return(http_connection)

        allow(http_connection).to receive(:open_timeout=)
        allow(http_connection).to receive(:read_timeout=)
        allow(http_connection).to receive(:use_ssl=)

        allow(http_connection).to receive(:start).and_yield(http_connection)

        http_response = instance_double(::Net::HTTPResponse, body: response_body, code: response_code)
        allow(http_connection).to receive(:request).with(http_request).and_return(http_response)
      end

      it { is_expected.to be_a(Datadog::Core::Transport::HTTP::Negotiation::Response) }

      it { is_expected.to be_ok }
      it { is_expected.to have_attributes(:version => '42') }
      it { is_expected.to have_attributes(:endpoints => ['/info', '/v0/path']) }
      it { is_expected.to have_attributes(:config => { max_request_bytes: '1234' }) }
    end
  end
end
