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
        allow(dbl).to receive(:ip).and_return('127.0.0.1')

        allow(dbl).to receive(:each_header).and_return [
          ['HTTP_USER_AGENT', 'Ruby/0.0'],
          ['SERVER_NAME', 'example.com'],
          ['REMOTE_ADDR', '127.0.0.1']
        ]
        allow(dbl).to receive(:env).and_return(
          'HTTP_USER_AGENT' => 'Ruby/0.0',
          'SERVER_NAME' => 'example.com',
          'REMOTE_ADDR' => '127.0.0.1'
        )

        dbl
      end

      let(:rack_response) do
        dbl = double

        allow(dbl).to receive(:headers).and_return([])

        dbl
      end

      let(:waf_result) do
        dbl = double

        allow(dbl).to receive(:data).and_return([])

        dbl
      end

      let(:event_count) { 1 }

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

            described_class.record(*events)
          end

          trace_op.flush!
        end

        it 'records an event on the trace' do
          expect(trace.send(:meta)).to eq(
            '_dd.appsec.json' => '{"triggers":[]}',
            'http.host' => 'example.com',
            'http.useragent' => 'Ruby/0.0',
            'http.request.headers.user-agent' => 'Ruby/0.0',
            'network.client.ip' => '127.0.0.1',
            '_dd.origin' => 'appsec',
            '_dd.p.dm' => '-5',
          )
        end

        it 'marks the trace to be kept' do
          expect(trace.sampling_priority).to eq Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
        end
      end

      context 'with no event' do
        let(:event_count) { 0 }

        let(:trace) do
          trace_op.measure('request') do |span|
            events.each { |e| e[:span] = span }

            described_class.record(*events)
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

      context 'with many traces' do
        let(:rate_limit) { 100 }
        let(:trace_count) { rate_limit * 2 }

        let(:traces) do
          Array.new(trace_count) do
            trace_op = Datadog::Tracing::TraceOperation.new(**options)

            trace_op.measure('request') do |span|
              events.each { |e| e[:span] = span }

              described_class.record(*events)
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
