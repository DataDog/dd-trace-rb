require "datadog/core"
require "datadog/core/ddsketch"
require "datadog/core/ddsketch_pprof/ddsketch_pb"

RSpec.describe Datadog::Core::DDSketch::Pure do
  subject(:sketch) { described_class.new }

  describe "mapping constants" do
    it "matches the libdatadog defaults so the wire format is compatible" do
      expect(described_class::RELATIVE_ACCURACY).to eq(0.007751937984496124)
      expect(described_class::GAMMA).to eq(1.015625)
      expect(described_class::INDEX_OFFSET).to eq(1338.5)
      expect(described_class::MAX_BINS).to eq(2048)
    end
  end

  describe "#add" do
    it "adds a point to the sketch" do
      expect { sketch.add(123.456) }.to change { sketch.count }.from(0.0).to(1.0)
    end

    it "returns the sketch" do
      expect(sketch.add(123.456)).to be sketch
    end

    it "accepts zero, counting it in the zero bucket" do
      expect { sketch.add(0) }.to change { sketch.count }.from(0.0).to(1.0)
    end

    context "when the point is a negative number" do
      it "raises an error matching the native implementation" do
        expect { sketch.add(-1.0) }.to raise_error(::RuntimeError, "DDSketch add failed: point is invalid")
      end
    end

    context "when the point is not finite" do
      it "raises for NaN" do
        expect { sketch.add(Float::NAN) }.to raise_error(::RuntimeError, "DDSketch add failed: point is invalid")
      end

      it "raises for Infinity" do
        expect { sketch.add(Float::INFINITY) }.to raise_error(::RuntimeError, "DDSketch add failed: point is invalid")
      end
    end
  end

  describe "#add_with_count" do
    it "adds a point with count to the sketch" do
      expect { sketch.add_with_count(10.0, 5.0) }.to change { sketch.count }.from(0.0).to(5.0)
    end

    it "returns the sketch" do
      expect(sketch.add_with_count(10.0, 5.0)).to be sketch
    end

    context "when the point is a negative number" do
      it "raises an error matching the native implementation" do
        expect { sketch.add_with_count(-1.0, 1.0) }.to raise_error(::RuntimeError, "DDSketch add_with_count failed: point is invalid")
      end
    end

    context "when the count is not finite" do
      it "raises for NaN" do
        expect { sketch.add_with_count(1.0, Float::NAN) }.to raise_error(::RuntimeError, "DDSketch add_with_count failed: count is invalid")
      end
    end
  end

  describe "#count" do
    it "returns zero for an empty sketch" do
      expect(sketch.count).to eq(0.0)
    end

    it "sums added points" do
      sketch.add(1.0)
      sketch.add(2.0)
      sketch.add(3.0)
      expect(sketch.count).to eq(3.0)
    end

    it "includes zero-bucket points" do
      5.times { sketch.add(0) }
      expect(sketch.count).to eq(5.0)
    end
  end

  describe "#encode" do
    it "returns a binary string" do
      sketch.add(1.0)
      result = sketch.encode
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "resets the sketch for reuse" do
      sketch.add(1.0)
      sketch.add(2.0)
      sketch.add(3.0)
      expect { sketch.encode }.to change { sketch.count }.from(3.0).to(0.0)
    end

    it "round-trips through the DDSketch protobuf" do
      sketch.add(1.0)
      sketch.add(2.0)
      sketch.add(3.0)
      42.times { sketch.add(0) }

      decoded = Test::DDSketch.decode(sketch.encode)

      expect(decoded.mapping.gamma).to eq(described_class::GAMMA)
      expect(decoded.mapping.indexOffset).to eq(described_class::INDEX_OFFSET)
      expect(decoded.zeroCount).to eq(42.0)
      bins_total = decoded.positiveValues.contiguousBinCounts.sum
      expect(bins_total).to eq(3.0)
    end

    it "encodes an empty sketch to just the mapping and empty stores" do
      # mapping{gamma, index_offset} + empty positive store + empty negative store, no zero_count
      expected = ["0a1209000000000040f03f110000000000ea944012001a00"].pack("H*")
      expect(sketch.encode).to eq(expected)
    end

    # These decode-based assertions pin the mapping and store behaviour on every engine
    # (including the JRuby/TruffleRuby deployment targets), where the byte-parity-vs-native
    # test below cannot run.
    it "maps a value to the expected logarithmic bin" do
      sketch.add(1.0) # ln(1.0) == 0, so index == floor(INDEX_OFFSET) == 1338

      decoded = Test::DDSketch.decode(sketch.encode)
      expect(decoded.positiveValues.contiguousBinIndexOffset).to eq(1338)
      expect(decoded.positiveValues.contiguousBinCounts).to eq([1.0])
    end

    it "preserves the total count when the store collapses" do
      sketch.add(0.0)      # zero bucket
      sketch.add(1e-300)   # forces a very low bin, spanning past MAX_BINS
      3.times { sketch.add(0.5) }

      decoded = Test::DDSketch.decode(sketch.encode)
      total = decoded.zeroCount + decoded.positiveValues.contiguousBinCounts.sum
      expect(total).to eq(5.0)
      expect(decoded.zeroCount).to eq(1.0)
    end
  end

  context "when the native extension is available" do
    before { skip("libdatadog native extension not available") unless Datadog::Core::DDSketch.supported? }

    # The whole point of this port: it must be byte-identical to libdatadog's native
    # DDSketch so the agent/backend decode and merge mixed native+pure fleets identically.
    [
      [],
      [0.0, 0.0, 0.0],
      [0.001, 0.002, 0.0015, 0.05, 0.123, 0.42, 1.0, 2.5, 10.0],
      [1e-9, 1e-5, 0.1, 2.0, 25.0, 10_000.0, 1e6],
      [0.0, 1e-300, 0.5, 0.5, 0.5],
      Array.new(1000, 0.05),
      (1..3000).map { |i| i * 0.001 },
    ].each do |points|
      it "produces byte-identical output to the native extension for #{points.length} point(s)" do
        native = Datadog::Core::DDSketch.new
        pure = described_class.new
        points.each do |point|
          native.add(point)
          pure.add(point)
        end

        expect(pure.encode).to eq(native.encode)
      end
    end
  end
end
