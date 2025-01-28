# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/gateway/request'
require 'datadog/appsec/contrib/rack/reactive/request_body'
require 'datadog/appsec/reactive/engine'
require 'datadog/appsec/reactive/shared_examples'

require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Rack::Reactive::RequestBody do
  let(:engine) { Datadog::AppSec::Reactive::Engine.new }
  let(:request) do
    Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
      Rack::MockRequest.env_for(
        'http://example.com:8080/?a=foo',
        { method: 'POST', params: { 'foo' => 'bar' } }
      )
    )
  end

  describe '.publish' do
    it 'propagates request body attributes to the engine' do
      expect(engine).to receive(:publish).with('request.body', { 'foo' => 'bar' })

      described_class.publish(engine, request)
    end
  end

  describe '.subscribe' do
    let(:appsec_context) { instance_double(Datadog::AppSec::Context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with('request.body').and_call_original
        expect(appsec_context).to_not receive(:run_waf)
        described_class.subscribe(engine, appsec_context)
      end
    end

    context 'all addresses have been published' do
      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does call the waf context with the right arguments' do
        expect(engine).to receive(:subscribe).and_call_original

        expected_waf_arguments = { 'server.request.body' => { 'foo' => 'bar' } }
        expect(appsec_context).to receive(:run_waf)
          .with(expected_waf_arguments, {}, Datadog.configuration.appsec.waf_timeout)
          .and_return(waf_result)

        described_class.subscribe(engine, appsec_context)
        expect(described_class.publish(engine, request)).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { request }
    end
  end
end
