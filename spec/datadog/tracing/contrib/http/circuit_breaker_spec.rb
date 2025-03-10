require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'
require 'datadog/tracing/contrib/http/circuit_breaker'
require 'datadog/core/transport/ext'

RSpec.describe Datadog::Tracing::Contrib::HTTP::CircuitBreaker do
  subject(:circuit_breaker) { circuit_breaker_class.new }

  let(:circuit_breaker_class) { Class.new { include Datadog::Tracing::Contrib::HTTP::CircuitBreaker } }

  describe '#should_skip_tracing?' do
    subject(:should_skip_tracing?) { circuit_breaker.should_skip_tracing?(request) }

    let(:request) { ::Net::HTTP::Post.new('/some/path') }

    context 'given a normal request' do
      before do
        allow(circuit_breaker).to receive(:internal_request?)
          .with(request)
          .and_return(false)

        allow(Datadog::Tracing).to receive(:active_span).and_return(nil)
      end

      it { is_expected.to be false }
    end

    context 'given a request that is a Datadog request' do
      before do
        allow(circuit_breaker).to receive(:internal_request?)
          .with(request)
          .and_return(true)
      end

      it { is_expected.to be true }
    end

    context 'when the request has an active HTTP request span' do
      let(:active_span) do
        instance_double(
          Datadog::Tracing::Span,
          name: Datadog::Tracing::Contrib::HTTP::Ext::SPAN_REQUEST
        )
      end

      before do
        allow(circuit_breaker).to receive(:internal_request?)
          .with(request)
          .and_return(false)

        allow(Datadog::Tracing).to receive(:active_span).and_return(active_span)
      end

      it { is_expected.to be true }
    end
  end

  describe '#internal_request?' do
    subject(:internal_request?) { circuit_breaker.internal_request?(request) }

    context 'given an HTTP request' do
      context "when the #{Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION} header" do
        context 'is present' do
          let(:request) { ::Net::HTTP::Post.new('/some/path', headers) }
          let(:headers) { { Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION => Datadog::VERSION::STRING } }

          it { is_expected.to be true }
        end

        context 'is missing' do
          let(:request) { ::Net::HTTP::Post.new('/some/path') }

          it { is_expected.to be false }
        end
      end

      context 'with the DD-Internal-Untraced-Request header' do
        context 'is present' do
          let(:request) { ::Net::HTTP::Post.new('/some/path', headers) }
          let(:headers) { { 'DD-Internal-Untraced-Request' => 'anything' } }

          it { is_expected.to be true }
        end

        context 'is missing' do
          let(:request) { ::Net::HTTP::Post.new('/some/path') }

          it { is_expected.to be false }
        end
      end
    end
  end

  describe '#should_skip_distributed_tracing?' do
    subject(:should_skip_distributed_tracing?) { circuit_breaker.should_skip_distributed_tracing?(client_config) }

    let(:client_config) { nil }
    let(:distributed_tracing) { true }
    let(:appsec_standalone) { false }
    let(:active_trace) { nil }
    let(:distributed_appsec_event) { nil }

    before do
      allow(Datadog.configuration.tracing[:http]).to receive(:[]).with(:distributed_tracing).and_return(distributed_tracing)
      allow(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(appsec_standalone)
      allow(Datadog::Tracing).to receive(:active_trace).and_return(active_trace)
      allow(active_trace).to receive(:get_tag).with('_dd.p.appsec').and_return(distributed_appsec_event) if active_trace
    end

    context 'when distributed tracing is enabled' do
      it { is_expected.to be false }
    end

    context 'when distributed tracing is disabled' do
      let(:distributed_tracing) { false }

      it { is_expected.to be true }
    end

    context 'when appsec standalone is enabled' do
      let(:appsec_standalone) { true }

      context 'when there is no active trace' do
        it { is_expected.to be true }
      end

      context 'when there is an active trace' do
        let(:active_trace) { instance_double(Datadog::Tracing::TraceOperation) }

        context 'when the active trace has no distributed appsec event' do
          it { is_expected.to be true }
        end

        context 'when the active trace has a distributed appsec event' do
          # This should act like standalone appsec is disabled, as it does not return in the
          # `if Datadog.configuration.appsec.standalone.enabled` block
          # so we're only testing the "no client config, distributed tracing enabled" case here
          let(:distributed_appsec_event) { '1' }

          it { is_expected.to be false }
        end
      end
    end

    context 'given a client config with distributed_tracing disabled' do
      let(:client_config) { { distributed_tracing: false } }

      it { is_expected.to be true }
    end

    context 'given a client config with distributed_tracing enabled' do
      let(:client_config) { { distributed_tracing: true } }

      it { is_expected.to be false }
    end
  end
end
