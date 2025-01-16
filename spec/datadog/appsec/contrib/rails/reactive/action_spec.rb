# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rails/reactive/action'
require 'datadog/appsec/contrib/rails/gateway/request'
require 'datadog/appsec/reactive/engine'
require 'datadog/appsec/reactive/shared_examples'

require 'action_dispatch'

RSpec.describe Datadog::AppSec::Contrib::Rails::Reactive::Action do
  let(:engine) { Datadog::AppSec::Reactive::Engine.new }
  let(:request) do
    request_env = Rack::MockRequest.env_for(
      'http://example.com:8080/?a=foo',
      { method: 'POST', params: { 'foo' => 'bar' }, 'action_dispatch.request.path_parameters' => { id: '1234' } }
    )

    rails_request = if ActionDispatch::TestRequest.respond_to?(:create)
                      ActionDispatch::TestRequest.create(request_env)
                    else
                      ActionDispatch::TestRequest.new(request_env)
                    end

    Datadog::AppSec::Contrib::Rails::Gateway::Request.new(rails_request)
  end

  describe '.publish' do
    it 'propagates request attributes to the engine' do
      expect(engine).to receive(:publish).with('rails.request.body', { 'foo' => 'bar' })
      expect(engine).to receive(:publish).with('rails.request.route_params', { id: '1234' })

      described_class.publish(engine, request)
    end
  end

  describe '.subscribe' do
    let(:appsec_context) { instance_double(Datadog::AppSec::Context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with('rails.request.body', 'rails.request.route_params').and_call_original
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

        expected_waf_arguments = {
          'server.request.body' => { 'foo' => 'bar' },
          'server.request.path_params' => { id: '1234' }
        }

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
