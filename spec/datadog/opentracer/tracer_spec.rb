require 'spec_helper'

require 'datadog/tracing/tracer'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::Tracer do
  subject(:tracer) { described_class.new(writer: writer) }

  let(:writer) { FauxWriter.new }

  after { writer.stop }

  ### Datadog::OpenTracing::Tracer behavior ###

  describe '#initialize' do
    context 'when given options' do
      subject(:tracer) { described_class.new(**options) }

      let(:options) { { enabled: double } }
      let(:datadog_tracer) { double('datadog_tracer') }

      before do
        expect(Datadog::Tracing::Tracer).to receive(:new)
          .with(**options)
          .and_return(datadog_tracer)
      end

      it { expect(tracer.datadog_tracer).to be(datadog_tracer) }
    end
  end

  describe '#datadog_tracer' do
    subject(:datadog_tracer) { tracer.datadog_tracer }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Tracer) }
  end

  ### Implemented OpenTracing::Tracer behavior ###

  describe '#scope_manager' do
    subject(:scope_manager) { tracer.scope_manager }

    it { is_expected.to be_a_kind_of(Datadog::OpenTracer::ThreadLocalScopeManager) }
  end

  describe '#start_active_span' do
    subject(:span) { tracer.start_active_span(name) }

    let(:name) { 'opentracing_span' }

    it { is_expected.to be_a_kind_of(Datadog::OpenTracer::ThreadLocalScope) }

    context 'when a block is given' do
      it do
        expect { |b| tracer.start_active_span(name, &b) }.to yield_with_args(
          a_kind_of(Datadog::OpenTracer::ThreadLocalScope)
        )
      end
    end
  end

  describe '#start_span' do
    subject(:span) { tracer.start_span(name) }

    let(:name) { 'opentracing_span' }

    it { is_expected.to be_a_kind_of(Datadog::OpenTracer::Span) }
  end

  describe '#inject' do
    subject(:inject) { tracer.inject(span_context, format, carrier) }

    let(:span_context) { instance_double(OpenTracing::SpanContext) }
    let(:carrier) { instance_double(OpenTracing::Carrier) }

    shared_context 'by propagator' do
      before do
        expect(propagator).to receive(:inject)
          .with(span_context, carrier)
      end
    end

    context 'when the format is' do
      context 'OpenTracing::FORMAT_TEXT_MAP' do
        include_context 'by propagator'
        let(:format) { OpenTracing::FORMAT_TEXT_MAP }
        let(:propagator) { Datadog::OpenTracer::TextMapPropagator }

        it { expect { inject }.to_not output.to_stdout }
        it { is_expected.to be nil }
      end

      context 'OpenTracing::FORMAT_BINARY' do
        include_context 'by propagator'
        let(:format) { OpenTracing::FORMAT_BINARY }
        let(:propagator) { Datadog::OpenTracer::BinaryPropagator }

        it { expect { inject }.to_not output.to_stdout }
        it { is_expected.to be nil }
      end

      context 'OpenTracing::FORMAT_RACK' do
        include_context 'by propagator'
        let(:format) { OpenTracing::FORMAT_RACK }
        let(:propagator) { Datadog::OpenTracer::RackPropagator }

        it { expect { inject }.to_not output.to_stdout }
        it { is_expected.to be nil }
      end

      context 'unknown' do
        let(:format) { double('unknown format') }

        it { expect { inject }.to output(/Unknown inject format/).to_stderr }
      end
    end
  end

  describe '#extract' do
    subject(:extract) { tracer.extract(format, carrier) }

    let(:carrier) { instance_double(OpenTracing::Carrier) }
    let(:span_context) { instance_double(Datadog::OpenTracer::SpanContext) }

    shared_context 'by propagator' do
      before do
        expect(propagator).to receive(:extract)
          .with(carrier)
          .and_return(span_context)
      end
    end

    context 'when the format is' do
      context 'OpenTracing::FORMAT_TEXT_MAP' do
        include_context 'by propagator'
        let(:format) { OpenTracing::FORMAT_TEXT_MAP }
        let(:propagator) { Datadog::OpenTracer::TextMapPropagator }

        it { expect { extract }.to_not output.to_stdout }
        it { is_expected.to be span_context }
      end

      context 'OpenTracing::FORMAT_BINARY' do
        include_context 'by propagator'
        let(:format) { OpenTracing::FORMAT_BINARY }
        let(:propagator) { Datadog::OpenTracer::BinaryPropagator }

        it { expect { extract }.to_not output.to_stdout }
        it { is_expected.to be span_context }
      end

      context 'OpenTracing::FORMAT_RACK' do
        include_context 'by propagator'
        let(:format) { OpenTracing::FORMAT_RACK }
        let(:propagator) { Datadog::OpenTracer::RackPropagator }

        it { expect { extract }.to_not output.to_stdout }
        it { is_expected.to be span_context }
      end

      context 'unknown' do
        let(:format) { double('unknown format') }

        before { expect { extract }.to output(/Unknown extract format/).to_stderr }

        it { is_expected.to be nil }
      end
    end
  end
end
