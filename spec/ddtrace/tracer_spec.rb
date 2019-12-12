require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  let(:writer) { FauxWriter.new }
  subject(:tracer) { described_class.new(writer: writer) }

  describe '#trace' do
    let(:name) { 'span.name' }
    let(:options) { {} }

    context 'given a block' do
      subject(:trace) { tracer.trace(name, options, &block) }
      let(:block) { proc { result } }
      let(:result) { double('result') }

      context 'when starting a span' do
        it do
          expect { |b| tracer.trace(name, &b) }.to yield_with_args(
            a_kind_of(Datadog::Span)
          )
        end

        it { expect(trace).to eq(result) }

        it 'tracks the number of allocations made in the span' do
          skip 'Test unstable; improve stability before re-enabling.'
          skip 'Not supported for Ruby < 2.0' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')

          # Create and discard first trace.
          # When warming up, it might have more allocations than subsequent traces.
          tracer.trace(name) {}
          writer.spans

          # Then create traces to compare
          tracer.trace(name) {}
          tracer.trace(name) { Object.new }

          first, second = writer.spans

          # Different versions of Ruby will allocate a different number of
          # objects, so this is what works across the board.
          expect(second.allocations).to eq(first.allocations + 1)
        end
      end

      context 'when starting a span fails' do
        before(:each) do
          allow(tracer).to receive(:start_span).and_raise(error)
        end

        let(:error) { error_class.new }
        let(:error_class) { Class.new(StandardError) }

        it 'still yields to the block and does not raise an error' do
          expect do
            expect do |b|
              tracer.trace(name, &b)
            end.to yield_with_args(nil)
          end.to_not raise_error
        end
      end

      context 'when the block raises an error' do
        let(:block) { proc { raise error } }
        let(:error) { error_class.new }
        let(:error_class) { Class.new(StandardError) }

        context 'and the on_error option' do
          context 'is not provided' do
            it do
              expect_any_instance_of(Datadog::Span).to receive(:set_error)
                .with(error)
              expect { trace }.to raise_error(error)
            end
          end

          context 'is a block' do
            it 'yields to the error block and raises the error' do
              expect_any_instance_of(Datadog::Span).to_not receive(:set_error)
              expect do
                expect do |b|
                  tracer.trace(name, on_error: b.to_proc, &block)
                end.to yield_with_args(
                  a_kind_of(Datadog::Span),
                  error
                )
              end.to raise_error(error)
            end
          end
        end
      end
    end
  end

  describe '#active_root_span' do
    subject(:active_root_span) { tracer.active_root_span }
    let(:span) { instance_double(Datadog::Span) }

    it do
      expect(tracer.call_context).to receive(:current_root_span).and_return(span)
      is_expected.to be(span)
    end
  end

  describe '#active_correlation' do
    subject(:active_correlation) { tracer.active_correlation }

    context 'when a trace is active' do
      let(:span) { @span }

      around(:each) do |example|
        tracer.trace('test') do |span|
          @span = span
          example.run
        end
      end

      it 'produces an Datadog::Correlation::Identifier with data' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(active_correlation.trace_id).to eq(span.trace_id)
        expect(active_correlation.span_id).to eq(span.span_id)
      end
    end

    context 'when no trace is active' do
      it 'produces an empty Datadog::Correlation::Identifier' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(active_correlation.trace_id).to be 0
        expect(active_correlation.span_id).to be 0
      end
    end
  end

  describe '#set_service_info' do
    include_context 'tracer logging'

    # Ensure we have a clean `@done_once` before and after each test
    # so we can properly test the behavior here, and we don't pollute other tests
    before(:each) { Datadog::Patcher.instance_variable_set(:@done_once, nil) }
    after(:each) { Datadog::Patcher.instance_variable_set(:@done_once, nil) }

    before(:each) do
      # Call multiple times to assert we only log once
      tracer.set_service_info('service-A', 'app-A', 'app_type-A')
      tracer.set_service_info('service-B', 'app-B', 'app_type-B')
      tracer.set_service_info('service-C', 'app-C', 'app_type-C')
      tracer.set_service_info('service-D', 'app-D', 'app_type-D')
    end

    it 'generates a single deprecation warnings' do
      expect(log_buffer.length).to be > 1
      expect(log_buffer).to contain_line_with('Usage of set_service_info has been deprecated')
    end
  end
end
