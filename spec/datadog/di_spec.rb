require 'spec_helper'

RSpec.describe(Datadog::DI) do
  describe 'instrumentation counters' do
    before do
      described_class.remove_instance_variable('@instrumented_count')
    rescue
      nil
    end

    # The retrieval of kind-scoped count is tested in the inc/dec blocks.
    describe '#instrumented_count' do
      context 'when the counter is not initialized' do
        it 'is 0' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          expect(described_class.instance_variable_get('@instrumented_count')).to be nil
        end
      end

      context 'when counter is incremented' do
        it 'is 1' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count).to eq 1
        end
      end

      # Important: this test also exercises initialization of state in
      # the increment method.
      context 'when counter is incremented then decremented' do
        it 'is 0' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count).to eq 1

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count).to eq 0
        end
      end

      # Important: this test also exercises initialization of state in
      # the decrement method.
      context 'when counter is decremented then incremented' do
        it 'is 1' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count).to eq 1
        end
      end

      context 'when counter is decremented into negative' do
        it 'is 0 and warns' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count).to eq 0
        end
      end
    end

    describe '#instrumented_count_inc' do
      context 'valid kind' do
        it 'increases only the respective counter' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count(:line)).to eq 1
          expect(described_class.instrumented_count(:method)).to eq 0
        end
      end

      context 'invalid kind' do
        it 'raises an exception' do
          expect do
            described_class.instrumented_count_inc(:foo)
          end.to raise_error(ArgumentError, /Invalid kind: foo/)
        end
      end
    end

    describe '#instrumented_count_dec' do
      context 'valid kind' do
        it 'deccreases only the respective counter' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          described_class.instrumented_count_inc(:line)
          described_class.instrumented_count_inc(:method)

          expect(described_class.instance_variable_get('@instrumented_count')).to eq(line: 1, method: 1)

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count(:line)).to eq 0
          expect(described_class.instrumented_count(:method)).to eq 1
        end
      end

      context 'invalid kind' do
        it 'raises an exception' do
          expect do
            described_class.instrumented_count_inc(:foo)
          end.to raise_error(ArgumentError, /Invalid kind: foo/)
        end
      end
    end
  end
end
