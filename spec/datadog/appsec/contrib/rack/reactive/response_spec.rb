# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/scope'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/rack/gateway/response'
require 'datadog/appsec/contrib/rack/reactive/response'
require 'datadog/appsec/reactive/shared_examples'

RSpec.describe Datadog::AppSec::Contrib::Rack::Reactive::Response do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
  let(:processor_context) { instance_double(Datadog::AppSec::Processor::Context) }
  let(:scope) { instance_double(Datadog::AppSec::Scope, processor_context: processor_context) }
  let(:body) { ['Ok'] }
  let(:headers) { { 'content-type' => 'text/html', 'set-cookie' => 'foo' } }

  let(:response) do
    Datadog::AppSec::Contrib::Rack::Gateway::Response.new(
      body,
      200,
      headers,
      scope: scope,
    )
  end

  describe '.publish' do
    it 'propagates response attributes to the operation' do
      expect(operation).to receive(:publish).with('response.status', 200)
      expect(operation).to receive(:publish).with(
        'response.headers',
        headers,
      )
      described_class.publish(operation, response)
    end
  end

  describe '.subscribe' do
    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(operation).to receive(:subscribe).with(
          'response.status',
          'response.headers',
        ).and_call_original
        expect(processor_context).to_not receive(:run)
        described_class.subscribe(operation, processor_context)
      end
    end

    context 'waf arguments' do
      before do
        expect(operation).to receive(:subscribe).and_call_original
      end

      let(:waf_result) { double(:waf_result, status: :ok, timeout: false) }

      context 'all addresses have been published' do
        let(:expected_waf_arguments) do
          {
            'server.response.status' => '200',
            'server.response.headers' => {
              'content-type' => 'text/html',
              'set-cookie' => 'foo',
            },
            'server.response.headers.no_cookies' => {
              'content-type' => 'text/html',
            },
          }
        end

        it 'does call the waf context with the right arguments' do
          expect(processor_context).to receive(:run).with(
            expected_waf_arguments,
            Datadog.configuration.appsec.waf_timeout
          ).and_return(waf_result)
          described_class.subscribe(operation, processor_context)
          result = described_class.publish(operation, response)
          expect(result).to be_nil
        end
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { response }
      let(:waf_context) { processor_context }
    end
  end
end
