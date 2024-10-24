require 'datadog/appsec/spec_helper'
require 'datadog/appsec/event'

RSpec.describe Datadog::AppSec::Event do
  context 'ALLOWED_REQUEST_HEADERS' do
    it 'store the correct values' do
      expect(described_class::ALLOWED_REQUEST_HEADERS).to eq(
        [
          'x-forwarded-for',
          'x-client-ip',
          'x-real-ip',
          'x-forwarded',
          'x-cluster-client-ip',
          'forwarded-for',
          'forwarded',
          'via',
          'true-client-ip',
          'content-length',
          'content-type',
          'content-encoding',
          'content-language',
          'host',
          'user-agent',
          'accept',
          'accept-encoding',
          'accept-language'
        ]
      )
    end
  end

  context 'ALLOWED_RESPONSE_HEADERS' do
    it 'store the correct values' do
      expect(described_class::ALLOWED_RESPONSE_HEADERS).to eq(
        [
          'content-length',
          'content-type',
          'content-encoding',
          'content-language'
        ]
      )
    end
  end

  describe '.record' do
    before do
      # prevent rate limiter to bias tests
      Datadog::AppSec::RateLimiter.reset!
    end

    let(:options) { {} }
    let(:trace_op) { Datadog::Tracing::TraceOperation.new(**options) }
    let(:trace) { trace_op.flush! }

    let(:rack_request_headers) do
      {
        'user-agent' => 'Ruby/0.0',
        'SERVER_NAME' => 'example.com',
        'REMOTE_ADDR' => '127.0.0.1',
      }
    end

    let(:rack_response_headers) do
      {
        'content-type' => 'text/html'
      }
    end

    let(:rack_request) do
      dbl = double

      allow(dbl).to receive(:host).and_return('example.com')
      allow(dbl).to receive(:user_agent).and_return('Ruby/0.0')
      allow(dbl).to receive(:remote_addr).and_return('127.0.0.1')

      allow(dbl).to receive(:headers).and_return(rack_request_headers)

      dbl
    end

    let(:rack_response) do
      dbl = double

      allow(dbl).to receive(:headers).and_return(rack_response_headers)

      dbl
    end

    let(:waf_events) do
      [1, { a: :b }]
    end

    let(:waf_result) do
      dbl = double

      allow(dbl).to receive(:events).and_return(waf_events)
      allow(dbl).to receive(:derivatives).and_return(derivatives)

      dbl
    end

    let(:event_count) { 1 }
    let(:derivatives) { {} }

    let(:events) do
      Array.new(event_count) do
        {
          trace: trace_op,
          span: nil, # backfilled later
          request: rack_request,
          response: rack_response,
          waf_result: waf_result,
        }
      end
    end

    context 'with one event' do
      let(:trace) do
        trace_op.measure('request') do |span|
          events.each { |e| e[:span] = span }

          10.times do |i|
            trace_op.measure("span #{i}") {}
          end

          described_class.record(span, *events)
        end

        trace_op.flush!
      end

      let(:top_level_span) do
        trace.spans.find { |s| s.metrics['_dd.top_level'] && s.metrics['_dd.top_level'] > 0.0 }
      end

      let(:other_spans) do
        trace.spans - [top_level_span]
      end

      context 'request headers' do
        context 'allowed headers' do
          it 'records allowed headers' do
            expect(top_level_span.meta).to include('http.request.headers.user-agent' => 'Ruby/0.0')
          end
        end

        context 'discard not allowed headers' do
          let(:rack_request_headers) do
            {
              'not-supported-header' => 'foo',
            }
          end

          it 'does not records allowed headers' do
            expect(top_level_span.meta).to_not include('http.request.headers.not-supported-header')
          end
        end
      end

      context 'response headers' do
        context 'allowed headers' do
          it 'records allowed headers' do
            expect(top_level_span.meta).to include('http.response.headers.content-type' => 'text/html')
          end
        end

        context 'discard not allowed headers' do
          let(:rack_response_headers) do
            {
              'not-supported-header' => 'foo',
            }
          end

          it 'does not records allowed headers' do
            expect(top_level_span.meta).to_not include('http.response.headers.not-supported-header')
          end
        end
      end

      context 'http information' do
        it 'records http information' do
          expect(top_level_span.meta).to include('http.host' => 'example.com')
          expect(top_level_span.meta).to include('http.useragent' => 'Ruby/0.0')
          expect(top_level_span.meta).to include('network.client.ip' => '127.0.0.1')
        end
      end

      it 'records an event on the top level span' do
        expect(top_level_span.meta).to include('_dd.appsec.json' => '{"triggers":[1,{"a":"b"}]}')
        expect(top_level_span.meta).to include('_dd.origin' => 'appsec')
      end

      it 'records nothing on other spans' do
        other_spans.each do |other_span|
          expect(other_span.meta).to be_empty
        end
      end

      it 'marks the trace to be kept' do
        expect(trace.sampling_priority).to eq Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
      end

      context 'waf_result derivatives' do
        let(:derivatives) do
          {
            '_dd.appsec.s.req.headers' => [{ 'host' => [8], 'version' => [8] }]
          }
        end

        context 'JSON payload' do
          it 'uses JSON string when do not exceeds MIN_SCHEMA_SIZE_FOR_COMPRESSION' do
            stub_const('Datadog::AppSec::Event::MIN_SCHEMA_SIZE_FOR_COMPRESSION', 3000)
            meta = top_level_span.meta

            expect(meta['_dd.appsec.s.req.headers']).to eq('[{"host":[8],"version":[8]}]')
          end
        end

        context 'Compressed payload' do
          it 'uses compressed value when JSON string is bigger than MIN_SCHEMA_SIZE_FOR_COMPRESSION' do
            result = 'H4sIAOYoHGUAA4aphwAAAA='
            stub_const('Datadog::AppSec::Event::MIN_SCHEMA_SIZE_FOR_COMPRESSION', 1)
            expect(described_class).to receive(:compressed_and_base64_encoded).and_return(result)

            meta = top_level_span.meta

            expect(meta['_dd.appsec.s.req.headers']).to eq(result)
          end

          context 'with big derivatives' do
            let(:derivatives) do
              {
                '_dd.appsec.s.req.headers' => [
                  {
                    'host' => [8],
                    'version' => [8],
                    'foo' => [8],
                    'bar' => [8],
                    'baz' => [8],
                    'qux' => [8],
                    'quux' => [8],
                    'quuux' => [8],
                    'quuuux' => [8],
                    'quuuuux' => [8],
                    'quuuuuux' => [8],
                    'quuuuuuux' => [8],
                    'quuuuuuuux' => [8],
                    'quuuuuuuuux' => [8],
                    'quuuuuuuuuux' => [8],
                    'quuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuuuuuuux' => [8],
                    'quuuuuuuuuuuuuuuuuuuuuuuux' => [8],
                  }
                ]
              }
            end

            it 'has no newlines when encoded' do
              meta = top_level_span.meta

              expect(meta['_dd.appsec.s.req.headers']).to_not match(/\n/)
            end
          end
        end

        context 'derivative values exceed Event::MAX_ENCODED_SCHEMA_SIZE value' do
          it 'do not add derivative key to meta' do
            stub_const('Datadog::AppSec::Event::MAX_ENCODED_SCHEMA_SIZE', 1)
            meta = top_level_span.meta

            expect(meta['_dd.appsec.s.req.headers']).to be_nil
          end
        end
      end
    end

    context 'with no event' do
      let(:event_count) { 0 }

      let(:trace) do
        trace_op.measure('request') do |span|
          events.each { |e| e[:span] = span }

          described_class.record(span, *events)
        end

        trace_op.flush!
      end

      it 'does not mark the trace to be kept' do
        expect(trace.sampling_priority).to eq nil
      end

      it 'does not attempt to record in the trace' do
        expect(described_class).to_not receive(:record_via_span)

        expect(trace).to_not be nil
      end

      it 'does not call the rate limiter' do
        expect_any_instance_of(Datadog::AppSec::RateLimiter).to_not receive(:limit)

        expect(trace).to_not be nil
      end
    end

    context 'with no span' do
      let(:event_count) { 1 }

      it 'does not attempt to record in the trace' do
        expect(described_class).to_not receive(:record_via_span)

        described_class.record(nil, events)
      end

      it 'does not call the rate limiter' do
        expect_any_instance_of(Datadog::AppSec::RateLimiter).to_not receive(:limit)

        described_class.record(nil, events)
      end
    end

    context 'with many traces' do
      before do
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
        allow(Datadog::AppSec::RateLimiter).to receive(:trace_rate_limit).and_return(rate_limit)
      end

      let(:rate_limit) { 50 }
      let(:trace_count) { rate_limit * 2 }

      let(:traces) do
        Array.new(trace_count) do
          trace_op = Datadog::Tracing::TraceOperation.new(**options)

          trace_op.measure('request') do |span|
            events.each { |e| e[:span] = span }

            described_class.record(span, *events)
          end

          trace_op.keep!
        end
      end

      it 'rate limits event recording' do
        expect(described_class).to receive(:record_via_span).exactly(rate_limit).times.and_call_original

        expect(traces).to have_attributes(count: trace_count)
      end
    end
  end

  describe '.tag_and_keep!' do
    let(:with_trace) { true }
    let(:with_span) { true }

    let(:waf_actions) { [] }
    let(:waf_result) do
      dbl = double

      allow(dbl).to receive(:actions).and_return(waf_actions)

      dbl
    end

    let(:scope) do
      scope_trace = nil
      scope_span = nil

      trace_operation = Datadog::Tracing::TraceOperation.new
      trace_operation.measure('root') do |span, trace|
        scope_trace = trace if with_trace
        scope_span = span if with_span
      end

      dbl = double

      allow(dbl).to receive(:trace).and_return(scope_trace)
      allow(dbl).to receive(:service_entry_span).and_return(scope_span)

      dbl
    end

    before do
      # prevent rate limiter to bias tests
      Datadog::AppSec::RateLimiter.reset!

      described_class.tag_and_keep!(scope, waf_result)
    end

    context 'with no actions' do
      it 'does not add appsec.blocked tag to span' do
        expect(scope.service_entry_span.send(:meta)).to_not include('appsec.blocked')
        expect(scope.service_entry_span.send(:meta)['appsec.event']).to eq('true')
        expect(scope.trace.send(:meta)['_dd.p.dm']).to eq('-5')
        expect(scope.trace.send(:meta)['_dd.p.appsec']).to eq('1')
      end
    end

    context 'with block action' do
      let(:waf_actions) { ['block'] }

      it 'adds appsec.blocked tag to span' do
        expect(scope.service_entry_span.send(:meta)['appsec.blocked']).to eq('true')
        expect(scope.service_entry_span.send(:meta)['appsec.event']).to eq('true')
        expect(scope.trace.send(:meta)['_dd.p.dm']).to eq('-5')
        expect(scope.trace.send(:meta)['_dd.p.appsec']).to eq('1')
      end
    end

    context 'without service_entry_span' do
      let(:with_span) { false }

      it 'does not add appsec span tags but still add distributed tags' do
        expect(scope.service_entry_span).to be nil
        expect(scope.trace.send(:meta)['_dd.p.dm']).to eq('-5')
        expect(scope.trace.send(:meta)['_dd.p.appsec']).to eq('1')
      end
    end

    context 'without trace' do
      let(:with_trace) { false }

      context 'with no actions' do
        it 'does not add distributed tags but still add appsec span tags' do
          expect(scope.trace).to be nil
          expect(scope.service_entry_span.send(:meta)['appsec.blocked']).to be nil
          expect(scope.service_entry_span.send(:meta)['appsec.event']).to eq('true')
        end
      end

      context 'with block action' do
        let(:waf_actions) { ['block'] }

        it 'does not add distributed tags but still add appsec span tags' do
          expect(scope.trace).to be nil
          expect(scope.service_entry_span.send(:meta)['appsec.blocked']).to eq('true')
          expect(scope.service_entry_span.send(:meta)['appsec.event']).to eq('true')
        end
      end
    end
  end
end
