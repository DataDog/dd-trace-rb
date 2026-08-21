# frozen_string_literal: true

require "spec_helper"
require "datadog/appsec/route_normalizer"

RSpec.describe Datadog::AppSec::RouteNormalizer::RouteText do
  describe ".escape" do
    it "escapes route text into normalized route form" do
      aggregate_failures "route text escaping" do
        expect(described_class.escape("users")).to eq("users")
        expect(described_class.escape("/users/path")).to eq("/users/path")
        expect(described_class.escape("a-b_c.d~e")).to eq("a-b_c.d~e")
        expect(described_class.escape("hello world")).to eq("hello%20world")
        expect(described_class.escape("a+b")).to eq("a%2Bb")
        expect(described_class.escape("café")).to eq("caf%C3%A9")
        expect(described_class.escape("{id}")).to eq("%7Bid%7D")
        expect(described_class.escape("%2F")).to eq("%252F")
        expect(described_class.escape("")).to eq("")
      end
    end

    it "returns the input object when escaping is not needed" do
      text = "users"
      expect(described_class.escape(text)).to equal(text)
    end

    it "returns UTF-8 escaped text" do
      expect(described_class.escape("café").encoding).to eq(Encoding::UTF_8)
    end
  end
end
