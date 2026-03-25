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

  describe '.activate_context' do
    before do
      allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
      allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
      allow(Datadog::Tracing).to receive(:active_span).and_return(span)
      described_class.activate_context(gateway)
    end

    context 'when security engine is available' do
      after { Datadog::AppSec::Context.deactivate }

      let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: runner) }
      let(:runner) { double('runner', finalize!: nil) }
      let(:trace) { double('trace') }
      let(:span) { double('span', set_metric: nil) }

      it 'activates AppSec context' do
        gateway.push('aws_lambda.request.start', event)
        expect(Datadog::AppSec::Context.active).to be_a(Datadog::AppSec::Context)
      end

      it 'sets appsec enabled metric on span' do
        gateway.push('aws_lambda.request.start', event)
        expect(span).to have_received(:set_metric).with('_dd.appsec.enabled', 1)
      end
    end

    context 'when security engine is not available' do
      let(:security_engine) { nil }
      let(:trace) { nil }
      let(:span) { nil }

      it { expect { gateway.push('aws_lambda.request.start', event) }.not_to raise_error }

      it 'does not activate context' do
        gateway.push('aws_lambda.request.start', event)
        expect(Datadog::AppSec::Context.active).to be_nil
      end
    end
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
        let(:waf_result) do
          double('waf_result', match?: true, attributes: [], actions: {}, keep?: false)
        end

        before do
          allow(Datadog::AppSec::Event).to receive(:tag)
          allow(Datadog::AppSec::ActionsHandler).to receive(:handle)
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
        let(:waf_result) do
          double('waf_result', match?: true, attributes: [], actions: {}, keep?: true)
        end

        before do
          allow(Datadog::AppSec::Event).to receive(:tag)
          allow(Datadog::AppSec::ActionsHandler).to receive(:handle)
          allow(Datadog::AppSec::TraceKeeper).to receive(:keep!)
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
      before do
        allow(Datadog::AppSec::Context).to receive(:active).and_return(context)
        allow(Datadog::AppSec::Context).to receive(:deactivate)
        allow(Datadog::AppSec::Event).to receive(:record)
        allow(context).to receive(:export_metrics)
        allow(context).to receive(:export_request_telemetry)
      end

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

      it 'calls Event.record' do
        gateway.push('aws_lambda.response.start', response)
        expect(Datadog::AppSec::Event).to have_received(:record).with(context, request: nil)
      end

      it 'exports metrics' do
        gateway.push('aws_lambda.response.start', response)
        expect(context).to have_received(:export_metrics)
      end

      it 'exports request telemetry' do
        gateway.push('aws_lambda.response.start', response)
        expect(context).to have_received(:export_request_telemetry)
      end

      it 'deactivates the context' do
        gateway.push('aws_lambda.response.start', response)
        expect(Datadog::AppSec::Context).to have_received(:deactivate)
      end

      context 'when WAF matches' do
        let(:waf_result) do
          double('waf_result', match?: true, attributes: [], actions: {}, keep?: false)
        end

        before do
          allow(Datadog::AppSec::Event).to receive(:tag)
          allow(Datadog::AppSec::ActionsHandler).to receive(:handle)
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

      context 'when finalize raises' do
        before do
          allow(Datadog::AppSec::Event).to receive(:record).and_raise(StandardError, 'boom')
        end

        it 'still deactivates the context' do
          expect { gateway.push('aws_lambda.response.start', response) }.to raise_error(StandardError, 'boom')
          expect(Datadog::AppSec::Context).to have_received(:deactivate)
        end
      end
    end
  end

  describe '.watch' do
    before do
      allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
      allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
      allow(Datadog::Tracing).to receive(:active_span).and_return(span)
      allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
      described_class.watch
    end

    after { Datadog::AppSec::Context.deactivate rescue nil }

    let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: runner) }
    let(:runner) { double('runner', run: waf_result, finalize!: nil, ruleset_version: '1.0', waf_addresses: []) }
    let(:trace) { double('trace', 'sampling_priority=' => nil) }
    let(:span) { double('span', set_metric: nil, set_tag: nil, set_tags: nil, type: 'web', id: 1) }
    let(:waf_result) do
      double('waf_result', match?: false, attributes: [], actions: {}, keep?: false,
        events: [], derivatives: {}, duration_ns: 0, duration_ext_ns: 0,
        timeout?: false, error?: false, input_truncated?: false)
    end

    it 'registers all three watchers so full request→response flow works' do
      gateway.push('aws_lambda.request.start', event)

      context = Datadog::AppSec::Context.active
      expect(context).to be_a(Datadog::AppSec::Context)
      expect(context.state[:request]).to be_a(Datadog::AppSec::Contrib::AwsLambda::Gateway::Request)

      allow(Datadog::AppSec::Event).to receive(:record)
      allow(context).to receive(:export_metrics)
      allow(context).to receive(:export_request_telemetry)

      gateway.push('aws_lambda.response.start', response)
      expect(Datadog::AppSec::Context.active).to be_nil
    end
  end
end
