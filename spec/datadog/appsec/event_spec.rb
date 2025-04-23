# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/event'

RSpec.describe Datadog::AppSec::Event do
  describe '.record' do
    before { Datadog::AppSec::RateLimiter.reset! }

    context 'when multiple spans present and a single security event with attack is recorded' do
      before { stub_const('Datadog::AppSec::Event::ALLOWED_REQUEST_HEADERS', ['user-agent']) }

      let(:top_level_span) { trace.spans.find { |span| span.metrics['_dd.top_level'].to_f > 0.0 } }
      let(:trace) do
        trace_op = Datadog::Tracing::TraceOperation.new
        trace_op.measure('request') do |span|
          2.times { |i| trace_op.measure("other span #{i}") { 'noop' } }

          events = [
            {
              trace: trace_op,
              span: span,
              request: rack_request,
              response: rack_response,
              waf_result: waf_result,
            }
          ]

          described_class.record(span, *events)
        end
        trace_op.flush!
      end

      let(:rack_request) do
        instance_double(
          Datadog::AppSec::Contrib::Rack::Gateway::Request,
          headers: { 'unknown-header' => 'hello', 'user-agent' => 'Ruby/0.0' },
          host: 'example.com',
          user_agent: 'Ruby/0.0',
          remote_addr: '127.0.0.1'
        )
      end

      let(:rack_response) do
        instance_double(
          Datadog::AppSec::Contrib::Rack::Gateway::Response,
          headers: { 'mystery-header' => '42', 'content-type' => 'text/html' }
        )
      end

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [1],
          actions: {},
          derivatives: {
            '_dd.appsec.s.req.headers' => [{ 'host' => [8], 'version' => [8] }]
          },
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0
        )
      end

      it 'keeps allowed HTTP headers and discards the rest' do
        expect(top_level_span.meta).to include(
          'http.request.headers.user-agent' => 'Ruby/0.0',
          'http.response.headers.content-type' => 'text/html'
        )
        expect(top_level_span.meta).not_to include(
          'http.request.headers.unknown-header',
          'http.response.headers.mystery-header'
        )
      end

      it 'sets HTTP information' do
        expect(top_level_span.meta).to include(
          'http.host' => 'example.com',
          'http.useragent' => 'Ruby/0.0',
          'network.client.ip' => '127.0.0.1'
        )
      end

      it 'sets origin and AppSec trigger information' do
        expect(top_level_span.meta).to include('_dd.appsec.json' => '{"triggers":[1]}')
        expect(top_level_span.meta).to include('_dd.origin' => 'appsec')
      end

      it 'marks the trace to be kept and sets the sampling priority to ASM' do
        expect(trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)
        expect(trace.sampling_decision_maker).to eq(Datadog::Tracing::Sampling::Ext::Decision::ASM)
      end

      it 'does not set AppSec information on non-top-level spans' do
        other_spans = trace.spans.reject { |span| span == top_level_span }

        expect(other_spans).not_to be_empty
        expect(other_spans).to all(have_attributes(meta: be_empty))
      end

      it 'sets WAF derivatives as uncompressed JSON string when they are small' do
        stub_const('Datadog::AppSec::CompressedJson::MIN_SIZE_FOR_COMPRESSION', 3000)

        expect(top_level_span.meta['_dd.appsec.s.req.headers']).to eq('[{"host":[8],"version":[8]}]')
      end

      it 'sets WAF derivatives as compressed JSON string when they are large' do
        stub_const('Datadog::AppSec::CompressedJson::MIN_SIZE_FOR_COMPRESSION', 1)
        allow(Datadog::AppSec::CompressedJson).to receive(:dump).and_return('H4sIAOYoHGUAA4aphwAAAA=')

        expect(top_level_span.meta['_dd.appsec.s.req.headers']).to eq('H4sIAOYoHGUAA4aphwAAAA=')
      end

      it 'does not set WAF derivatives when they exceed the max compressed size' do
        stub_const('Datadog::AppSec::Event::DERIVATIVE_SCHEMA_MAX_COMPRESSED_SIZE', 1)

        expect(top_level_span.meta['_dd.appsec.s.req.headers']).to be_nil
      end
    end

    context 'when no security events are recorded' do
      let(:trace) do
        trace_op = Datadog::Tracing::TraceOperation.new
        trace_op.measure('request') { |span| described_class.record(span,) }
        trace_op.flush!
      end

      it 'does not record the event and does not mark the trace to be kept' do
        expect(trace.sampling_priority).to be_nil
        expect(described_class).to_not receive(:record_via_span)
      end
    end

    context 'when no span is provided' do
      let(:trace) do
        trace_op = Datadog::Tracing::TraceOperation.new
        trace_op.measure('request') { |_span| described_class.record(nil, 'does not matter') }
        trace_op.flush!
      end

      it 'does not record the event and does not mark the trace to be kept' do
        expect(trace.sampling_priority).to be_nil
        expect(described_class).to_not receive(:record_via_span)
      end
    end

    context 'when traces count exceeds the rate limit' do
      before do
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
        allow(Datadog::AppSec::RateLimiter).to receive(:trace_rate_limit).and_return(50)
      end

      let(:traces) do
        Array.new(100) do
          trace_op = Datadog::Tracing::TraceOperation.new
          trace_op.measure('request') { |span| described_class.record(span, 'does not matter') }
          trace_op.keep!
        end
      end

      it 'performs exactly 50 recordings' do
        expect(described_class).to receive(:record_via_span).exactly(50).times
        expect(traces.count).to eq(100)
      end
    end
  end

  describe '.tag_and_keep!' do
    let(:with_trace) { true }
    let(:with_span) { true }

    let(:waf_actions) { {} }
    let(:waf_result) do
      dbl = double

      allow(dbl).to receive(:actions).and_return(waf_actions)

      dbl
    end

    let(:context) do
      context_trace = nil
      context_span = nil

      trace_operation = Datadog::Tracing::TraceOperation.new
      trace_operation.measure('root') do |span, trace|
        context_trace = trace if with_trace
        context_span = span if with_span
      end

      dbl = instance_double(Datadog::AppSec::Context)

      allow(dbl).to receive(:trace).and_return(context_trace)
      allow(dbl).to receive(:span).and_return(context_span)

      dbl
    end

    before do
      # prevent rate limiter to bias tests
      Datadog::AppSec::RateLimiter.reset!

      described_class.tag_and_keep!(context, waf_result)
    end

    context 'with no actions' do
      it 'does not add appsec.blocked tag to span' do
        expect(context.span.send(:meta)).to_not include('appsec.blocked')
        expect(context.span.send(:meta)['appsec.event']).to eq('true')
        expect(context.trace.send(:meta)['_dd.p.dm']).to eq('-5')
        expect(context.trace.send(:meta)['_dd.p.ts']).to eq('02')
      end
    end

    context 'with block_request action' do
      let(:waf_actions) do
        { 'block_request' => { 'grpc_status_code' => '10', 'status_code' => '403', 'type' => 'auto' } }
      end

      it 'adds appsec.blocked tag to span' do
        expect(context.span.send(:meta)['appsec.blocked']).to eq('true')
        expect(context.span.send(:meta)['appsec.event']).to eq('true')
        expect(context.trace.send(:meta)['_dd.p.dm']).to eq('-5')
        expect(context.trace.send(:meta)['_dd.p.ts']).to eq('02')
      end
    end

    context 'with redirect_request action' do
      let(:waf_actions) do
        { 'redirect_request' => { 'status_code' => '302', 'location' => 'https://datadoghq.com' } }
      end

      it 'adds appsec.blocked tag to span' do
        expect(context.span.send(:meta)['appsec.blocked']).to eq('true')
        expect(context.span.send(:meta)['appsec.event']).to eq('true')
      end
    end

    context 'without span' do
      let(:with_span) { false }

      it 'does not add appsec span tags but still add distributed tags' do
        expect(context.span).to be nil
        expect(context.trace.send(:meta)['_dd.p.dm']).to eq('-5')
        expect(context.trace.send(:meta)['_dd.p.ts']).to eq('02')
      end
    end

    context 'without trace' do
      let(:with_trace) { false }

      context 'with no actions' do
        it 'does not add distributed tags but still add appsec span tags' do
          expect(context.trace).to be nil
          expect(context.span.send(:meta)['appsec.blocked']).to be nil
          expect(context.span.send(:meta)['appsec.event']).to eq('true')
        end
      end

      context 'with block action' do
        let(:waf_actions) do
          { 'block_request' => { 'grpc_status_code' => '10', 'status_core' => '403', 'type' => 'auto' } }
        end

        it 'does not add distributed tags but still add appsec span tags' do
          expect(context.trace).to be nil
          expect(context.span.send(:meta)['appsec.blocked']).to eq('true')
          expect(context.span.send(:meta)['appsec.event']).to eq('true')
        end
      end
    end
  end
end
