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
      Datadog::AppSec::RateLimiter.reset!(:traces)
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
            result = "H4sIAOYoHGUAA4aphwAAAA=\n"
            stub_const('Datadog::AppSec::Event::MIN_SCHEMA_SIZE_FOR_COMPRESSION', 1)
            expect(described_class).to receive(:compressed_and_base64_encoded).and_return(result)

            meta = top_level_span.meta

            expect(meta['_dd.appsec.s.req.headers']).to eq(result)
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
        expect(Datadog::AppSec::RateLimiter).to_not receive(:limit)

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
        expect(Datadog::AppSec::RateLimiter).to_not receive(:limit)

        described_class.record(nil, events)
      end
    end

    context 'with many traces' do
      let(:rate_limit) { 100 }
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
end
