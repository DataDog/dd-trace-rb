require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::Tracer do
    include_context 'OpenTracing helpers'

    subject(:tracer) { described_class.new }

    describe '#scope_manager' do
      subject(:scope_manager) { tracer.scope_manager }
      it { is_expected.to be(OpenTracing::ScopeManager::NOOP_INSTANCE) }
    end

    describe '#start_active_span' do
      subject(:span) { tracer.start_active_span(name) }
      let(:name) { 'opentracing_span' }

      it { is_expected.to be OpenTracing::Scope::NOOP_INSTANCE }

      context 'when a block is given' do
        it { expect { |b| tracer.start_active_span(name, &b) }.to yield_with_args(OpenTracing::Scope::NOOP_INSTANCE) }
      end
    end

    describe '#start_span' do
      subject(:span) { tracer.start_span(name) }
      let(:name) { 'opentracing_span' }

      it { is_expected.to be OpenTracing::Span::NOOP_INSTANCE }
    end

    describe '#inject' do
      subject(:inject) { tracer.inject(span_context, format, carrier) }
      let(:span_context) { instance_double(OpenTracing::SpanContext) }
      let(:carrier) { instance_double(OpenTracing::Carrier) }

      context 'when the format is' do
        context 'OpenTracing::FORMAT_TEXT_MAP' do
          let(:format) { OpenTracing::FORMAT_TEXT_MAP }
          it { expect { inject }.to_not output.to_stdout }
          it { is_expected.to be nil }
        end

        context 'OpenTracing::FORMAT_BINARY' do
          let(:format) { OpenTracing::FORMAT_BINARY }
          it { expect { inject }.to_not output.to_stdout }
          it { is_expected.to be nil }
        end

        context 'OpenTracing::FORMAT_RACK' do
          let(:format) { OpenTracing::FORMAT_RACK }
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

      context 'when the format is' do
        context 'OpenTracing::FORMAT_TEXT_MAP' do
          let(:format) { OpenTracing::FORMAT_TEXT_MAP }
          it { expect { extract }.to_not output.to_stdout }
          it { is_expected.to be OpenTracing::SpanContext::NOOP_INSTANCE }
        end

        context 'OpenTracing::FORMAT_BINARY' do
          let(:format) { OpenTracing::FORMAT_BINARY }
          it { expect { extract }.to_not output.to_stdout }
          it { is_expected.to be OpenTracing::SpanContext::NOOP_INSTANCE }
        end

        context 'OpenTracing::FORMAT_RACK' do
          let(:format) { OpenTracing::FORMAT_RACK }
          it { expect { extract }.to_not output.to_stdout }
          it { is_expected.to be OpenTracing::SpanContext::NOOP_INSTANCE }
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
