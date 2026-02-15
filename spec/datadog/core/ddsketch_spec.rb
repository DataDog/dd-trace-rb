require 'datadog/core/ddsketch_pprof/ddsketch_pb'

RSpec.describe Datadog::Core::DDSketch do
  context 'when DDSketch is supported' do
    subject(:sketch) { described_class.new }

    describe '#add' do
      it 'adds a point to the sketch' do
        expect { sketch.add(123.456) }.to change { sketch.count }.from(0.0).to(1.0)
      end

      it 'returns the sketch' do
        expect(sketch.add(123.456)).to be sketch
      end

      context 'when the point is a negative number' do
        it 'raises an error' do
          expect { sketch.add(-1.0) }.to raise_error(::RuntimeError) do |error|
            expect(error.message).to eq('DDSketch add failed: point is invalid')
          end
        end
      end
    end

    describe '#add_with_count' do
      it 'adds a point with count to the sketch' do
        expect { sketch.add_with_count(10.0, 5.0) }.to change { sketch.count }.from(0.0).to(5.0)
      end

      it 'returns the sketch' do
        expect(sketch.add_with_count(10.0, 5.0)).to be sketch
      end

      context 'when the point is a negative number' do
        it 'raises an error' do
          expect { sketch.add_with_count(-1.0, 1.0) }.to raise_error(::RuntimeError) do |error|
            expect(error.message).to eq('DDSketch add_with_count failed: point is invalid')
          end
        end
      end
    end

    describe '#count' do
      subject(:count) { sketch.count }

      context 'when sketch is empty' do
        it 'returns zero' do
          expect(count).to be 0.0
        end
      end

      context 'when sketch has points' do
        before do
          sketch.add(1.0)
          sketch.add(2.0)
          sketch.add(3.0)
        end

        it 'returns the total count' do
          expect(count).to be 3.0
        end
      end
    end

    describe '#encode' do
      subject(:encode) { sketch.encode }

      before do
        sketch.add(1.0)
        sketch.add(2.0)
        sketch.add(3.0)
      end

      it 'returns a binary string' do
        result = encode
        expect(result).to be_a(String)
        expect(result.encoding).to eq(Encoding::BINARY)
      end

      it 'resets the sketch for reuse' do
        expect { sketch.encode }.to change { sketch.count }.from(3.0).to(0.0)
      end

      it 'can be decoded' do
        42.times { sketch.add(0) }
        decoded = Test::DDSketch.decode(encode)

        # @ivoanjo: Not amazingly interesting, but just a simple sanity check that the round trip works
        expect(decoded.zeroCount).to be(42.0)
      end
    end
  end
end
