# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/component'

RSpec.describe Datadog::Core::Remote::Negotiation do
  shared_context 'HTTP connection stub' do
    before do
      request_class = ::Net::HTTP::Get
      http_request = instance_double(request_class)
      allow(request_class).to receive(:new).and_return(http_request)

      http_connection = instance_double(::Net::HTTP)
      allow(::Net::HTTP).to receive(:new).and_return(http_connection)

      allow(http_connection).to receive(:open_timeout=)
      allow(http_connection).to receive(:read_timeout=)
      allow(http_connection).to receive(:use_ssl=)

      allow(http_connection).to receive(:start).and_yield(http_connection)

      if respond_to?(:request_exception)
        allow(http_connection).to receive(:request).with(http_request).and_raise(request_exception)
      else
        http_response = instance_double(::Net::HTTPResponse, body: response_body, code: response_code)
        allow(http_connection).to receive(:request).with(http_request).and_return(http_response)
      end
    end
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  describe '#endpoint?' do
    include_context 'HTTP connection stub'

    subject(:endpoint?) { negotiation.endpoint?('/foo') }
    let(:suppress_logging) { {} }
    let(:negotiation) { described_class.new(settings, agent_settings, suppress_logging: suppress_logging) }

    context 'when /info exists' do
      let(:response_code) { 200 }
      let(:response_body) do
        {
          'endpoints' => [
            '/info',
            '/foo',
          ],
        }.to_json
      end

      it do
        expect(Datadog.logger).to_not receive(:warn)

        expect(endpoint?).to be true
      end

      it do
        expect(Datadog.logger).to receive(:warn)

        expect(negotiation.endpoint?('/bar')).to be false
      end

      context 'when logging for :no_config_endpoint is suppressed' do
        let(:suppress_logging) { { no_config_endpoint: true } }

        it 'does not log an error' do
          expect(Datadog.logger).to_not receive(:warn)

          expect(negotiation.endpoint?('/bar')).to be false
        end
      end
    end

    context 'when /info does not exist' do
      let(:response_code) { 404 }
      let(:response_body) { '404 page not found' }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { expect(endpoint?).to be false }

      context 'on repeated errors' do
        it 'only logs once' do
          negotiation.endpoint?('/foo')
          negotiation.endpoint?('/foo')
        end
      end
    end

    context 'when agent rejects request' do
      let(:response_code) { 400 }
      let(:response_body) { '400 bad request' }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { expect(endpoint?).to be false }

      context 'on repeated errors' do
        it 'only logs once' do
          negotiation.endpoint?('/foo')
          negotiation.endpoint?('/foo')
        end
      end
    end

    context 'when agent is in error' do
      let(:response_code) { 500 }
      let(:response_body) { '500 internal server error' }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { expect(endpoint?).to be false }

      context 'on repeated errors' do
        it 'only logs once' do
          negotiation.endpoint?('/foo')
          negotiation.endpoint?('/foo')
        end
      end
    end

    context 'when agent causes an error' do
      let(:response_code) { 200 }
      let(:response_body) do
        'unparseable response'
      end

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { expect(endpoint?).to be false }

      context 'on repeated errors' do
        it 'only logs once' do
          negotiation.endpoint?('/foo')
          negotiation.endpoint?('/foo')
        end
      end
    end

    context 'when agent is unreachable' do
      let(:request_exception) { Errno::ECONNREFUSED.new }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { expect(endpoint?).to be false }

      context 'on repeated errors' do
        it 'only logs once' do
          negotiation.endpoint?('/foo')
          negotiation.endpoint?('/foo')
        end
      end
    end
  end
end
