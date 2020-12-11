require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace'
require 'ddtrace/contrib/http/circuit_breaker'

RSpec.describe Datadog::Contrib::HTTP::CircuitBreaker do
  subject(:circuit_breaker) { circuit_breaker_class.new }
  let(:circuit_breaker_class) { Class.new { include Datadog::Contrib::HTTP::CircuitBreaker } }

  describe '#should_skip_tracing?' do
    subject(:should_skip_tracing?) { circuit_breaker.should_skip_tracing?(request, tracer) }
    let(:request) { ::Net::HTTP::Post.new('/some/path') }
    let(:tracer) { instance_double(Datadog::Tracer) }

    context 'given a normal request' do
      before do
        allow(circuit_breaker).to receive(:datadog_http_request?)
          .with(request)
          .and_return(false)

        allow(tracer).to receive(:active_span).and_return(nil)
      end

      it { is_expected.to be false }
    end

    context 'given a request that is a Datadog request' do
      before do
        allow(circuit_breaker).to receive(:datadog_http_request?)
          .with(request)
          .and_return(true)
      end

      it { is_expected.to be true }
    end

    context 'when the request has an active HTTP request span' do
      let(:active_span) { instance_double(Datadog::Span, name: Datadog::Contrib::HTTP::Ext::SPAN_REQUEST) }

      before do
        allow(circuit_breaker).to receive(:datadog_http_request?)
          .with(request)
          .and_return(false)

        allow(tracer).to receive(:active_span).and_return(active_span)
      end

      it { is_expected.to be true }
    end
  end

  describe '#datadog_http_request?' do
    subject(:datadog_http_request?) { circuit_breaker.datadog_http_request?(request) }

    context 'given an HTTP request' do
      context "when the #{Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION} header" do
        context 'is present' do
          let(:request) { ::Net::HTTP::Post.new('/some/path', headers) }
          let(:headers) { { Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Datadog::VERSION::STRING } }
          it { is_expected.to be true }
        end

        context 'is missing' do
          let(:request) { ::Net::HTTP::Post.new('/some/path') }
          it { is_expected.to be false }
        end
      end
    end

    context 'integration' do
      context 'given a request from' do
        let(:request) { @request }

        subject(:send_traces) do
          # Capture the HTTP request directly from the transport,
          # to make sure we have legitimate example.
          expect(::Net::HTTP::Post).to receive(:new).and_wrap_original do |m, *args|
            @request = m.call(*args)
          end

          # The request may produce an error (because the transport cannot connect)
          # but ignore this... we just need the request, not a successful response.
          allow(Datadog.logger).to receive(:error)

          # Send a request, and make sure we captured it.
          transport.send_traces(get_test_traces(1))

          expect(@request).to be_a_kind_of(::Net::HTTP::Post)
        end

        context 'a Datadog Net::HTTP transport' do
          before { expect(::Net::HTTP).to receive(:new) }

          let(:transport) { Datadog::Transport::HTTP.default }
          it { is_expected.to be true }
        end

        context 'a Datadog UDS transport' do
          let(:transport) do
            Datadog::Transport::HTTP.default do |t|
              t.adapter :unix, '/tmp/ddagent/trace.sock'
            end
          end

          it { is_expected.to be true }
        end
      end
    end
  end
end
