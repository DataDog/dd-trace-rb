require 'datadog/appsec/spec_helper'
require 'datadog/appsec/event'

RSpec.describe Datadog::AppSec::Event do
  context 'self' do
    describe '#record' do
      before do
        # prevent rate limiter to bias tests
        Datadog::AppSec::RateLimiter.reset!(:traces)
      end

      let(:options) { {} }
      let(:trace_op) { Datadog::Tracing::TraceOperation.new(**options) }
      let(:trace) { trace_op.flush! }

      let(:rack_request) do
        dbl = double

        allow(dbl).to receive(:host).and_return('example.com')
        allow(dbl).to receive(:user_agent).and_return('Ruby/0.0')
        allow(dbl).to receive(:remote_addr).and_return('127.0.0.1')

        allow(dbl).to receive(:headers).and_return [
          ['user-agent', 'Ruby/0.0'],
          ['SERVER_NAME', 'example.com'],
          ['REMOTE_ADDR', '127.0.0.1']
        ]

        dbl
      end

      let(:rack_response) do
        dbl = double

        allow(dbl).to receive(:headers).and_return([])

        dbl
      end

      let(:waf_result) do
        dbl = double

        allow(dbl).to receive(:events).and_return([])
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

        it 'records an event on the top level span' do
          expect(top_level_span.meta).to eq(
            '_dd.appsec.json' => '{"triggers":[]}',
            'http.host' => 'example.com',
            'http.useragent' => 'Ruby/0.0',
            'http.request.headers.user-agent' => 'Ruby/0.0',
            'network.client.ip' => '127.0.0.1',
            '_dd.origin' => 'appsec',
          )
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

          it 'adds derivatives after comporessing and encode to Base64 to the top level span meta' do
            meta = top_level_span.meta
            gzip = described_class.send(:gzip, JSON.dump([{ 'host' => [8], 'version' => [8] }]))
            result = Base64.encode64(gzip)

            expect(meta['_dd.appsec.s.req.headers']).to eq result
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
end
