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

  describe '.handle_request' do
    before { described_class.handle_request(gateway) }

    context 'when AppSec context is not active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect { gateway.push('aws_lambda.request.start', event) }.not_to raise_error }
    end

    context 'when AppSec context is active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(context) }

      let(:context) do
        instance_double(
          Datadog::AppSec::Context,
          run_waf: waf_result,
          events: events,
          trace: double('trace'),
          span: double('span'),
          state: {},
        )
      end
      let(:events) { [] }
      let(:waf_result) do
        double('waf_result', match?: false, attributes: [], actions: {}, keep?: false)
      end

      it 'runs WAF with request addresses' do
        gateway.push('aws_lambda.request.start', event)

        expect(context).to have_received(:run_waf).with(
          hash_including('server.request.method' => 'GET', 'server.request.uri.raw' => '/test'),
          {},
          anything,
        )
      end

      it 'stores Request on context state' do
        gateway.push('aws_lambda.request.start', event)

        request = context.state[:request]
        expect(request).to be_a(Datadog::AppSec::Contrib::AwsLambda::Gateway::Request)
        expect(request.host).to eq('example.com')
        expect(request.user_agent).to eq('TestBot')
        expect(request.remote_addr).to eq('10.0.0.1')
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
          gateway.push('aws_lambda.request.start', event)
          expect(events).not_to be_empty
          expect(events.first).to be_a(Datadog::AppSec::SecurityEvent)
        end

        it 'tags the context' do
          gateway.push('aws_lambda.request.start', event)
          expect(Datadog::AppSec::Event).to have_received(:tag).with(context, waf_result)
        end

        it 'handles actions' do
          gateway.push('aws_lambda.request.start', event)
          expect(Datadog::AppSec::ActionsHandler).to have_received(:handle).with({})
        end
      end

      context 'when WAF result has attributes but no match' do
        let(:waf_result) do
          double('waf_result', match?: false, attributes: ['something'], actions: {}, keep?: false)
        end

        it 'pushes a security event' do
          gateway.push('aws_lambda.request.start', event)
          expect(events).not_to be_empty
        end
      end

      context 'when WAF does not match and has no attributes' do
        it 'does not push events' do
          gateway.push('aws_lambda.request.start', event)
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
          gateway.push('aws_lambda.request.start', event)
          expect(Datadog::AppSec::TraceKeeper).to have_received(:keep!).with(context.trace)
        end
      end
    end
  end

  describe '.handle_response' do
    before { described_class.handle_response(gateway) }

    context 'when AppSec context is not active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect { gateway.push('aws_lambda.response.start', response) }.not_to raise_error }
    end

    context 'when AppSec context is active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(context) }

      let(:context) do
        instance_double(
          Datadog::AppSec::Context,
          run_waf: waf_result,
          events: events,
          trace: double('trace'),
          span: double('span'),
          state: {},
        )
      end
      let(:events) { [] }
      let(:waf_result) do
        double('waf_result', match?: false, attributes: [], actions: {}, keep?: false)
      end

      it 'runs WAF with response addresses' do
        gateway.push('aws_lambda.response.start', response)

        expect(context).to have_received(:run_waf).with(
          hash_including('server.response.status' => '200'),
          {},
          anything,
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
          gateway.push('aws_lambda.response.start', response)
          expect(events).not_to be_empty
        end

        it 'tags the context' do
          gateway.push('aws_lambda.response.start', response)
          expect(Datadog::AppSec::Event).to have_received(:tag).with(context, waf_result)
        end
      end
    end
  end

  describe '.watch' do
    before do
      allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
      described_class.watch
    end

    context 'when AppSec context is active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(context) }

      let(:context) do
        instance_double(
          Datadog::AppSec::Context,
          run_waf: waf_result,
          events: [],
          trace: double('trace'),
          span: double('span'),
          state: {},
        )
      end
      let(:waf_result) do
        double('waf_result', match?: false, attributes: [], actions: {}, keep?: false)
      end

      it 'registers request and response watchers' do
        gateway.push('aws_lambda.request.start', event)
        expect(context.state[:request]).to be_a(Datadog::AppSec::Contrib::AwsLambda::Gateway::Request)

        gateway.push('aws_lambda.response.start', response)
        expect(context).to have_received(:run_waf).twice
      end
    end
  end
end
