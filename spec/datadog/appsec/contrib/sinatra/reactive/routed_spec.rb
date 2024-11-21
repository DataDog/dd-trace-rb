# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/sinatra/reactive/routed'
require 'datadog/appsec/contrib/rack/gateway/request'
require 'datadog/appsec/contrib/sinatra/gateway/route_params'
require 'datadog/appsec/reactive/engine'
require 'datadog/appsec/reactive/shared_examples'

require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Sinatra::Reactive::Routed do
  let(:engine) { Datadog::AppSec::Reactive::Engine.new }
  let(:request) do
    Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
      Rack::MockRequest.env_for(
        'http://example.com:8080/?a=foo',
        { 'REMOTE_ADDR' => '10.10.10.10', 'HTTP_CONTENT_TYPE' => 'text/html' }
      )
    )
  end
  let(:routed_params) { Datadog::AppSec::Contrib::Sinatra::Gateway::RouteParams.new({ id: '1234' }) }

  describe '.publish' do
    it 'propagates routed params attributes to the engine' do
      expect(engine).to receive(:publish).with('sinatra.request.route_params', { id: '1234' })

      described_class.publish(engine, [request, routed_params])
    end
  end

  describe '.subscribe' do
    let(:waf_context) { double(:waf_context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with('sinatra.request.route_params').and_call_original
        expect(waf_context).to_not receive(:run)
        described_class.subscribe(engine, waf_context)
      end
    end

    context 'all addresses have been published' do
      it 'does call the waf context with the right arguments' do
        expect(engine).to receive(:subscribe).and_call_original

        expected_waf_arguments = {
          'server.request.path_params' => { id: '1234' }
        }

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).with(
          expected_waf_arguments,
          {},
          Datadog.configuration.appsec.waf_timeout
        ).and_return(waf_result)
        described_class.subscribe(engine, waf_context)
        result = described_class.publish(engine, [request, routed_params])
        expect(result).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { [request, routed_params] }
    end
  end
end
