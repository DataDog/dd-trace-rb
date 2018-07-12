require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  subject(:tracer) { described_class.new(writer: FauxWriter.new) }

  describe '#trace' do
    let(:name) { 'span.name' }

    context 'given a block' do
      subject(:trace) { tracer.trace(name, &block) }
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
    end
  end
end
