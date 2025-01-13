# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/context'
require 'datadog/appsec/contrib/rack/gateway/response'
require 'datadog/appsec/contrib/rack/reactive/response'
require 'datadog/appsec/reactive/engine'
require 'datadog/appsec/reactive/shared_examples'

RSpec.describe Datadog::AppSec::Contrib::Rack::Reactive::Response do
  let(:engine) { Datadog::AppSec::Reactive::Engine.new }
  let(:processor_context) { instance_double(Datadog::AppSec::Processor::Context) }
  let(:context) { instance_double(Datadog::AppSec::Context, processor_context: processor_context) }
  let(:body) { ['Ok'] }
  let(:headers) { { 'content-type' => 'text/html', 'set-cookie' => 'foo' } }

  let(:response) do
    Datadog::AppSec::Contrib::Rack::Gateway::Response.new(
      body,
      200,
      headers,
      scope: context,
    )
  end

  describe '.publish' do
    it 'propagates response attributes to the engine' do
      expect(engine).to receive(:publish).with('response.status', 200)
      expect(engine).to receive(:publish).with(
        'response.headers',
        headers,
      )
      described_class.publish(engine, response)
    end
  end

  describe '.subscribe' do
    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with(
          'response.status',
          'response.headers',
        ).and_call_original
        expect(processor_context).to_not receive(:run)
        described_class.subscribe(engine, processor_context)
      end
    end

    context 'waf arguments' do
      before do
        expect(engine).to receive(:subscribe).and_call_original
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
            {},
            Datadog.configuration.appsec.waf_timeout
          ).and_return(waf_result)
          described_class.subscribe(engine, processor_context)
          result = described_class.publish(engine, response)
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
