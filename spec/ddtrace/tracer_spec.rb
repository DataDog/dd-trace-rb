require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  subject(:tracer) { described_class.new(writer: FauxWriter.new) }

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
end
