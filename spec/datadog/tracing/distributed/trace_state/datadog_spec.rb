require "spec_helper"

require "datadog/tracing/distributed/trace_state/datadog"

RSpec.describe Datadog::Tracing::Distributed::TraceState::Datadog do
  let(:codec) { described_class }

  describe "#build" do
    subject(:build) do
      described_class.new(
        sampling_priority: 1,
        origin: "synthetics",
        ts_parent_id: "000000000000000f",
        tags: {"_dd.p.test" => "value"},
        unknown_fields: "future:value;"
      ).build
    end

    it "builds the Datadog tracestate member" do
      is_expected.to eq("dd=p:000000000000000f;s:1;o:synthetics;t.test:value;future:value")
    end

    it "removes the trailing field separator" do
      expect(described_class.new(sampling_priority: 1).build).to eq("dd=s:1")
    end
  end

  describe "#decode" do
    subject(:decode) { codec.decode(input) }

    context "with a valid input" do
      [
        ["", {}],
        ["key=value", {"key" => "value"}],
        ["_key=value", {"_key" => "value"}],
        ["1key=digit", {"1key" => "digit"}],
        ["12345=678910", {"12345" => "678910"}],
        ["trailing=comma,", {"trailing" => "comma"}],
        ["value=with spaces", {"value" => "with spaces"}],
        ["value=with=equals", {"value" => "with=equals"}],
        ["trim= value ", {"trim" => "value"}],
        ["ascii@=~chars;", {"ascii@" => "~chars;"}],
        ["a=1,b=2,c=3", {"a" => "1", "b" => "2", "c" => "3"}],
      ].each do |input, expected|
        context "of value `#{input}`" do
          let(:input) { input }
          it { is_expected.to eq(expected) }
        end
      end
    end

    context "with an invalid input" do
      [
        "no_equals",
        "no_value=",
        "=no_key",
        "=",
        ",",
        ",=,",
        ",leading=comma",
        "key with=spaces",
        "out_of=range\ncharacter",
        "out\tof=range character",
      ].each do |input|
        context "of value `#{input}`" do
          let(:input) { input }
          it { expect { decode }.to raise_error(described_class::DecodingError) }
        end
      end
    end
  end

  describe "#encode" do
    subject(:encode) { codec.encode(input) }

    context "with a valid input" do
      [
        [{}, ""],
        [{"key" => "value"}, "key=value"],
        [{"key" => 1}, "key=1"],
        [{"a" => "1", "b" => "2", "c" => "3"}, "a=1,b=2,c=3"],
        [{"trim" => " value "}, "trim=value"],
      ].each do |input, expected|
        context "of value `#{input}`" do
          let(:input) { input }
          it { is_expected.to eq(expected) }
        end
      end
    end

    context "with an invalid input" do
      [
        {"key with" => "space"},
        {"key,with" => "comma"},
        {"value" => "with,comma"},
        {"key=with" => "equals"},
        {"" => "empty_key"},
        {"empty_value" => ""},
        {"🙅️" => "out of range characters"},
        {"out_of_range_characters" => "🙅️"},
      ].each do |input, _expected|
        context "of value `#{input}`" do
          let(:input) { input }
          it { expect { encode }.to raise_error(described_class::EncodingError) }
        end
      end
    end
  end

  describe "encode and decode" do
    let(:input) do
      {"key" => "value"}
    end

    let(:encoded_input) do
      "key=value"
    end

    it "decoding reverses encoding" do
      expect(codec.decode(codec.encode(input))).to eq(input)
    end

    it "encoding reverses decoding" do
      expect(codec.encode(codec.decode(encoded_input))).to eq(encoded_input)
    end
  end
end
