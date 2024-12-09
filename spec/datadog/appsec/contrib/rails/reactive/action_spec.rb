require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/rails/reactive/action'
require 'datadog/appsec/contrib/rails/gateway/request'
require 'datadog/appsec/reactive/shared_examples'

require 'action_dispatch'

RSpec.describe Datadog::AppSec::Contrib::Rails::Reactive::Action do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
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
    it 'propagates request attributes to the operation' do
      expect(operation).to receive(:publish).with('rails.request.body', { 'foo' => 'bar' })
      expect(operation).to receive(:publish).with('rails.request.route_params', { id: '1234' })

      described_class.publish(operation, request)
    end
  end

  describe '.subscribe' do
    let(:waf_context) { double(:waf_context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(operation).to receive(:subscribe).with('rails.request.body', 'rails.request.route_params').and_call_original
        expect(waf_context).to_not receive(:run)
        described_class.subscribe(operation, waf_context)
      end
    end

    context 'all addresses have been published' do
      it 'does call the waf context with the right arguments' do
        expect(operation).to receive(:subscribe).and_call_original

        expected_waf_arguments = {
          'server.request.body' => { 'foo' => 'bar' },
          'server.request.path_params' => { id: '1234' }
        }

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).with(
          expected_waf_arguments,
          {},
          Datadog.configuration.appsec.waf_timeout
        ).and_return(waf_result)
        described_class.subscribe(operation, waf_context)
        result = described_class.publish(operation, request)
        expect(result).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { request }
    end
  end
end
