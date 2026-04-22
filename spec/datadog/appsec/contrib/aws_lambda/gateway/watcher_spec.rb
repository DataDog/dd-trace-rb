# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/aws_lambda/gateway/watcher'

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  let(:event) do
    {
      'httpMethod' => 'GET',
      'path' => '/test',
      'headers' => {'Host' => 'example.com', 'User-Agent' => 'TestBot'},
      'requestContext' => {'identity' => {'sourceIp' => '10.0.0.1'}},
    }
  end

  let(:response) do
    {
      'statusCode' => 200,
      'headers' => {'Content-Type' => 'application/json'},
    }
  end

  let(:appsec_context) do
    instance_double(
      Datadog::AppSec::Context,
      run_waf: waf_result,
      events: events,
      trace: double('trace'),
      span: double('span')
    )
  end
  let(:events) { [] }
  let(:waf_result) do
    double('waf_result', match?: false, attributes: [], actions: {}, keep?: false)
  end

  describe '.handle_request' do
    subject(:push_request) do
      gateway.push(
        'aws_lambda.request.start',
        Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(event, context: appsec_context)
      )
    end

    before { described_class.handle_request(gateway) }

    context 'when AppSec context is not active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect { push_request }.not_to raise_error }
    end

    context 'when AppSec context is active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context) }

      it 'runs WAF with request addresses' do
        push_request

        expect(appsec_context).to have_received(:run_waf).with(
          hash_including('server.request.method' => 'GET', 'server.request.uri.raw' => '/test'),
          {},
          anything
        )
      end

      context 'when WAF matches' do
        before do
          allow(Datadog::AppSec::Event).to receive(:tag)
          allow(Datadog::AppSec::ActionsHandler).to receive(:handle)
        end

        let(:waf_result) do
          double('waf_result', match?: true, attributes: [], actions: {}, keep?: false)
        end

        it 'pushes a security event' do
          push_request

          expect(events).not_to be_empty
          expect(events.first).to be_a(Datadog::AppSec::SecurityEvent)
        end

        it 'tags the context' do
          push_request

          expect(Datadog::AppSec::Event).to have_received(:tag).with(appsec_context, waf_result)
        end

        it 'handles actions' do
          push_request

          expect(Datadog::AppSec::ActionsHandler).to have_received(:handle).with({})
        end
      end

      context 'when WAF result has attributes but no match' do
        let(:waf_result) do
          double('waf_result', match?: false, attributes: ['something'], actions: {}, keep?: false)
        end

        it 'pushes a security event' do
          push_request

          expect(events).not_to be_empty
        end
      end

      context 'when WAF does not match and has no attributes' do
        it 'does not push events' do
          push_request

          expect(events).to be_empty
        end
      end

      context 'when WAF match has keep? true' do
        before do
          allow(Datadog::AppSec::Event).to receive(:tag)
          allow(Datadog::AppSec::ActionsHandler).to receive(:handle)
          allow(Datadog::AppSec::TraceKeeper).to receive(:keep!)
        end

        let(:waf_result) do
          double('waf_result', match?: true, attributes: [], actions: {}, keep?: true)
        end

        it 'keeps the trace' do
          push_request

          expect(Datadog::AppSec::TraceKeeper).to have_received(:keep!).with(appsec_context.trace)
        end
      end
    end
  end

  describe '.handle_response' do
    subject(:push_response) do
      gateway.push(
        'aws_lambda.response.start',
        Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(response, context: appsec_context)
      )
    end

    before { described_class.handle_response(gateway) }

    context 'when AppSec context is not active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect { push_response }.not_to raise_error }
    end

    context 'when AppSec context is active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context) }

      it 'runs WAF with response addresses' do
        push_response

        expect(appsec_context).to have_received(:run_waf).with(
          hash_including('server.response.status' => '200'),
          {},
          anything
        )
      end

      context 'when WAF matches' do
        before do
          allow(Datadog::AppSec::Event).to receive(:tag)
          allow(Datadog::AppSec::ActionsHandler).to receive(:handle)
        end

        let(:waf_result) do
          double('waf_result', match?: true, attributes: [], actions: {}, keep?: false)
        end

        it 'pushes a security event' do
          push_response

          expect(events).not_to be_empty
        end

        it 'tags the context' do
          push_response

          expect(Datadog::AppSec::Event).to have_received(:tag).with(appsec_context, waf_result)
        end
      end
    end
  end

  describe '.watch' do
    before do
      allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
      allow(Datadog::AppSec::Context).to receive(:active).and_return(appsec_context)
      described_class.watch
    end

    it 'registers request and response watchers' do
      request_payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(event, context: appsec_context)
      response_payload = Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(response, context: appsec_context)

      gateway.push('aws_lambda.request.start', request_payload)
      gateway.push('aws_lambda.response.start', response_payload)

      expect(appsec_context).to have_received(:run_waf).twice
    end
  end
end
