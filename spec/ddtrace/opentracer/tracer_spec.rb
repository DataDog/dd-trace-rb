require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::Tracer do
    include_context 'OpenTracing helpers'

    subject(:tracer) { described_class.new(writer: FauxWriter.new) }

    ### Datadog::OpenTracing::Tracer behavior ###

    describe '#initialize' do
      context 'when given options' do
        subject(:tracer) { described_class.new(options) }
        let(:options) { double('options') }
        let(:datadog_tracer) { double('datadog_tracer') }

        before(:each) do
          expect(Datadog::Tracer).to receive(:new)
            .with(options)
            .and_return(datadog_tracer)
        end

        it { expect(tracer.datadog_tracer).to be(datadog_tracer) }
      end
    end

    describe '#datadog_tracer' do
      subject(:datadog_tracer) { tracer.datadog_tracer }
      it { is_expected.to be_a_kind_of(Datadog::Tracer) }
    end

    describe '#configure' do
      subject(:configure) { tracer.configure(options) }
      let(:options) { double('options') }

      before(:each) do
        expect(tracer.datadog_tracer).to receive(:configure)
          .with(options)
      end

      it { expect { configure }.to_not raise_error }
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
        before(:each) do
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
          it { expect { inject }.to output("Unknown inject format\n").to_stderr }
        end
      end
    end

    describe '#extract' do
      subject(:extract) { tracer.extract(format, carrier) }
      let(:carrier) { instance_double(OpenTracing::Carrier) }
      let(:span_context) { instance_double(Datadog::OpenTracer::SpanContext) }

      shared_context 'by propagator' do
        before(:each) do
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
          before(:each) { expect { extract }.to output("Unknown extract format\n").to_stderr }
          it { is_expected.to be nil }
        end
      end
    end
  end
end
