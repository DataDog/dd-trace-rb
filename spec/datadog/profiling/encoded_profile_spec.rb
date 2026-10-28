require "datadog/profiling/spec_helper"
require "datadog/profiling/encoded_profile"

RSpec.describe Datadog::Profiling::EncodedProfile do
  before do
    skip_if_profiling_not_supported
  end

  let(:start) { Time.at(1_700_000_001, 123_456_789, :nanosecond) }
  let(:finish) { Time.at(1_700_000_067, 987_654_321, :nanosecond) }

  describe ".from_custom" do
    subject(:profile) { described_class.from_custom(start, finish, bytes_string) }

    let(:bytes_string) { "custom\x00\xffpayload".b }

    it "returns an EncodedProfile with the exact binary bytes" do
      expect(profile).to be_a(described_class)
      expect(profile._native_bytes).to eq(bytes_string)
      expect(profile._native_bytes.encoding).to eq(Encoding::BINARY)
    end

    it "owns a copy independent of the source string" do
      original = bytes_string.dup
      created = profile
      bytes_string.replace("changed")

      expect(created._native_bytes).to eq(original)
    end

    it "returns independent byte strings" do
      profile._native_bytes.replace("changed")

      expect(profile._native_bytes).to eq(bytes_string)
    end

    it "keeps the payload after the source has been collected" do
      created = Thread.new { described_class.from_custom(start, finish, +"collected source") }.value
      GC.start

      expect(created._native_bytes).to eq("collected source")
    end

    it "releases unsent profiles during garbage collection" do
      Thread.new do
        100.times { described_class.from_custom(start, finish, "unsent\x00\xff".b) }
        nil
      end.join
      GC.start

      expect(profile._native_bytes).to eq(bytes_string)
    end

    context "with empty bytes" do
      let(:bytes_string) { "" }

      it "preserves the empty payload" do
        expect(profile._native_bytes).to eq("")
      end
    end

    context "with frozen bytes" do
      let(:bytes_string) { "frozen".freeze }

      it "copies the payload" do
        expect(profile._native_bytes).to eq("frozen")
      end
    end

    context "with a large payload" do
      let(:bytes_string) { "\x00\xff".b * 100_000 }

      it "preserves every byte" do
        expect(profile._native_bytes).to eq(bytes_string)
      end
    end

    context "with equal timestamps" do
      let(:finish) { start }

      it "accepts a zero duration" do
        expect(profile._native_bytes).to eq(bytes_string)
      end
    end

    context "with end before start" do
      let(:finish) { start - Rational(1, 1_000_000_000) }

      it "accepts end before start" do
        expect(profile._native_bytes).to eq(bytes_string)
      end
    end

    context "with a timestamp outside time_t's range" do
      let(:finish) { Time.at(2**100) }

      it "rejects the timestamp" do
        expect { profile }.to raise_error(ArgumentError, /time out of system range/)
      end
    end

    [nil, 123, "2026-01-01"].each do |invalid_time|
      it "rejects #{invalid_time.inspect} as start" do
        expect { described_class.from_custom(invalid_time, finish, bytes_string) }
          .to raise_error(TypeError, "start and end must be Time objects")
      end

      it "rejects #{invalid_time.inspect} as end" do
        expect { described_class.from_custom(start, invalid_time, bytes_string) }
          .to raise_error(TypeError, "start and end must be Time objects")
      end
    end

    [nil, 123, []].each do |invalid_bytes|
      it "rejects #{invalid_bytes.inspect} as bytes" do
        expect { described_class.from_custom(start, finish, invalid_bytes) }.to raise_error(TypeError, /T_STRING/)
      end
    end
  end
end
