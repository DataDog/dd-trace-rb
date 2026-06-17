# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/sinatra/gateway/watcher'
require 'datadog/appsec/contrib/sinatra/gateway/request'
require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Sinatra::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      run_waf: waf_result,
      events: [],
      state: {},
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

  describe '.watch_request_dispatch' do
    before do
      described_class.watch_request_dispatch(gateway)
      allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(100)
    end

    let(:gateway_request) do
      Datadog::AppSec::Contrib::Sinatra::Gateway::Request.new(
        Rack::MockRequest.env_for(
          'http://example.com/',
          {
            :method => 'POST',
            :input => 'name=john',
            'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
            Datadog::AppSec::Ext::CONTEXT_KEY => context
          }
        )
      )
    end

    context 'when the body is parsed and within the limit' do
      it 'runs WAF with the body and its byte length' do
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {'server.request.body' => {'name' => 'john'}, 'server.request.body.byte_length' => 9}, {}, anything
        )
      end

      it 'sets the web framework state' do
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(context.state[:web_framework]).to eq('sinatra')
      end
    end

    context 'when the body does not respond to size' do
      before do
        allow(gateway_request.request).to receive(:body).and_return(Object.new)
        allow(gateway_request.request).to receive(:content_length).and_return(42)
      end

      it 'runs WAF with the content length as byte length' do
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {'server.request.body' => {'name' => 'john'}, 'server.request.body.byte_length' => 42}, {}, anything
        )
      end
    end

    context 'when the body size is unknown' do
      before do
        gateway_request.env.delete('CONTENT_LENGTH')
        gateway_request.env['rack.input'] = unsized_io
      end

      let(:unsized_io) do
        StringIO.new('name=john').tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      context 'when the body fits within the limit' do
        it 'runs WAF with the body and its measured byte length' do
          gateway.push('sinatra.request.dispatch', gateway_request)

          expect(context).to have_received(:run_waf).with(
            {'server.request.body' => {'name' => 'john'}, 'server.request.body.byte_length' => 9}, {}, anything
          )
        end
      end

      context 'when the body exceeds the limit' do
        before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(4) }

        it 'does not run WAF' do
          gateway.push('sinatra.request.dispatch', gateway_request)

          expect(context).not_to have_received(:run_waf)
        end

        it 'does not parse the form body' do
          allow(gateway_request).to receive(:form_hash)
          gateway.push('sinatra.request.dispatch', gateway_request)

          expect(gateway_request).not_to have_received(:form_hash)
        end
      end

      context 'when body collection is disabled' do
        before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

        it 'does not run WAF' do
          gateway.push('sinatra.request.dispatch', gateway_request)

          expect(context).not_to have_received(:run_waf)
        end

        it 'does not measure the body' do
          allow(gateway_request).to receive(:body_bytesize)
          gateway.push('sinatra.request.dispatch', gateway_request)

          expect(gateway_request).not_to have_received(:body_bytesize)
        end
      end
    end

    context 'when the body exceeds the parsing size limit' do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(4) }

      it 'runs WAF with only the byte length' do
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(context).to have_received(:run_waf).with(
          {'server.request.body.byte_length' => 9}, {}, anything
        )
      end

      it 'does not parse the form body' do
        allow(gateway_request).to receive(:form_hash)

        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(gateway_request).not_to have_received(:form_hash)
      end
    end

    context 'when the parsing size limit is zero' do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

      it 'does not run WAF' do
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(context).not_to have_received(:run_waf)
      end

      it 'does not measure the body' do
        allow(gateway_request).to receive(:body_bytesize)
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(gateway_request).not_to have_received(:body_bytesize)
      end
    end

    context 'when no body was parsed' do
      let(:gateway_request) do
        Datadog::AppSec::Contrib::Sinatra::Gateway::Request.new(
          Rack::MockRequest.env_for(
            'http://example.com/',
            {:method => 'GET', Datadog::AppSec::Ext::CONTEXT_KEY => context}
          )
        )
      end

      it 'does not run WAF' do
        gateway.push('sinatra.request.dispatch', gateway_request)

        expect(context).not_to have_received(:run_waf)
      end
    end
  end
end
