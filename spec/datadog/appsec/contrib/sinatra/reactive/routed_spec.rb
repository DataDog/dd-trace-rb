# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/sinatra/reactive/routed'
require 'datadog/appsec/contrib/rack/gateway/request'
require 'datadog/appsec/contrib/sinatra/gateway/route_params'
require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Sinatra::Reactive::Routed do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
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
    it 'propagates routed params attributes to the operation' do
      expect(operation).to receive(:publish).with('sinatra.request.route_params', { id: '1234' })

      described_class.publish(operation, [request, routed_params])
    end
  end

  describe '.subscribe' do
    let(:waf_context) { double(:waf_context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(operation).to receive(:subscribe).with('sinatra.request.route_params').and_call_original
        expect(waf_context).to_not receive(:run)
        described_class.subscribe(operation, waf_context)
      end
    end

    context 'all addresses have been published' do
      it 'does call the waf context with the right arguments' do
        expect(operation).to receive(:subscribe).and_call_original

        expected_waf_arguments = {
          'server.request.path_params' => { id: '1234' }
        }

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).with(
          expected_waf_arguments,
          Datadog::AppSec.settings.waf_timeout
        ).and_return(waf_result)
        described_class.subscribe(operation, waf_context)
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end

    context 'waf result is a match' do
      it 'yields result and no blocking action' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :match, timeout: false, actions: [''])
        expect(waf_context).to receive(:run).and_return(waf_result)
        described_class.subscribe(operation, waf_context) do |result, block|
          expect(result).to eq(waf_result)
          expect(block).to eq(false)
        end
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end

      it 'yields result and blocking action. The publish method catches the resul as well' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :match, timeout: false, actions: ['block'])
        expect(waf_context).to receive(:run).and_return(waf_result)
        described_class.subscribe(operation, waf_context) do |result, block|
          expect(result).to eq(waf_result)
          expect(block).to eq(true)
        end
        publish_result, publish_block = described_class.publish(operation, [request, routed_params])
        expect(publish_result).to eq(waf_result)
        expect(publish_block).to eq(true)
      end
    end

    context 'waf result is ok' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_call' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_call, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_rule' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_rule, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_flow' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_flow, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end

    context 'waf result is no_rule' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :no_rule, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end

    context 'waf result is unknown' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :foo, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, [request, routed_params])
        expect(result).to be_nil
      end
    end
  end
end
