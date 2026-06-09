# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rails/gateway/watcher'
require 'datadog/appsec/contrib/rails/gateway/request'
require 'action_dispatch'

RSpec.describe Datadog::AppSec::Contrib::Rails::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      run_waf: waf_result,
      events: [],
      trace: instance_double(Datadog::Tracing::TraceOperation),
      span: instance_double(Datadog::Tracing::SpanOperation)
    )
  end

  let(:waf_result) do
    instance_double(
      Datadog::AppSec::SecurityEngine::Result::Ok,
      match?: false,
      attributes: [],
      actions: {},
      keep?: false
    )
  end

  describe '.watch_request_action' do
    before { described_class.watch_request_action(gateway) }

    let(:gateway_request) do
      instance_double(
        Datadog::AppSec::Contrib::Rails::Gateway::Request,
        env: {Datadog::AppSec::Ext::CONTEXT_KEY => context},
        route_params: {id: '1'},
        parsed_body: {'name' => 'john'},
        request: rack_request
      )
    end

    let(:rack_request) { instance_double(ActionDispatch::Request, body: StringIO.new('name=john'), content_length: 9) }

    context 'when the body is parsed and within the limit' do
      it 'runs WAF with path params, body and its byte length' do
        gateway.push('rails.request.action', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            'server.request.path_params' => {id: '1'},
            'server.request.body.byte_length' => 9,
            'server.request.body' => {'name' => 'john'}
          }, {}, anything
        )
      end
    end

    context 'when the body does not respond to size' do
      let(:rack_request) { instance_double(ActionDispatch::Request, body: Object.new, content_length: 42) }

      it 'runs WAF with the content length as byte length' do
        gateway.push('rails.request.action', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            'server.request.path_params' => {id: '1'},
            'server.request.body.byte_length' => 42,
            'server.request.body' => {'name' => 'john'}
          }, {}, anything
        )
      end
    end

    context 'when the body size cannot be determined' do
      let(:rack_request) { instance_double(ActionDispatch::Request, body: Object.new, content_length: 0) }

      it 'runs WAF with only the path params' do
        gateway.push('rails.request.action', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {'server.request.path_params' => {id: '1'}}, {}, anything
        )
      end
    end

    context 'when the body exceeds the parsing size limit' do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(4) }

      it 'runs WAF with path params and byte length but without the body' do
        gateway.push('rails.request.action', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            'server.request.path_params' => {id: '1'},
            'server.request.body.byte_length' => 9
          }, {}, anything
        )
      end

      it 'does not parse the body' do
        gateway.push('rails.request.action', gateway_request)

        expect(gateway_request).not_to have_received(:parsed_body)
      end
    end

    context 'when the parsing size limit is zero' do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

      it 'runs WAF with path params and byte length but without the body' do
        gateway.push('rails.request.action', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            'server.request.path_params' => {id: '1'},
            'server.request.body.byte_length' => 9
          }, {}, anything
        )
      end
    end

    context 'when there is no request body' do
      let(:rack_request) { instance_double(ActionDispatch::Request, body: StringIO.new(''), content_length: 0) }

      it 'runs WAF with only the path params' do
        gateway.push('rails.request.action', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {'server.request.path_params' => {id: '1'}}, {}, anything
        )
      end

      it 'does not parse the body' do
        gateway.push('rails.request.action', gateway_request)

        expect(gateway_request).not_to have_received(:parsed_body)
      end
    end
  end
end
