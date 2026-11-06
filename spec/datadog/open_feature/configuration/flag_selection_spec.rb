# frozen_string_literal: true

require "json"
require "spec_helper"
require_relative "../../../../tasks/lib/fixtures/ffe"
require "datadog/open_feature/configuration/flag_selection"

RSpec.describe Datadog::OpenFeature::Configuration::FlagSelection do
  def canonicalize(option)
    described_class.canonicalize(option)
  end

  describe ".canonicalize" do
    context "with the shared selection vectors" do
      fixture_root = File.join(File.expand_path("../../../..", __dir__), FfeFixtures::CACHE, FfeFixtures::COMMIT_SHA)
      vectors_file = File.join(fixture_root, "flag-selection", "selection-vectors.json")
      unless File.file?(vectors_file)
        raise "Flag selection vectors are not cached at #{vectors_file}. Run: bundle exec rake fixtures:ffe:download"
      end

      # Cases with a raw query test the server's percent-decoding and have no SDK expectation.
      sdk_cases = JSON.parse(File.read(vectors_file)).fetch("cases").select { |test_case| test_case.key?("sdk") }
      raise "No SDK cases in #{vectors_file}" if sdk_cases.empty?

      sdk_cases.each do |test_case|
        it test_case.fetch("name") do
          query = test_case.fetch("query")
          option = {}
          option[:tags] = query["selected_flag_tags"] if query.key?("selected_flag_tags")
          option[:key_patterns] = query["selected_flag_key_patterns"] if query.key?("selected_flag_key_patterns")
          expected = test_case.fetch("sdk")

          selection = canonicalize(option)

          if expected.key?("dropped")
            expect(selection).to be_dropped
            expect(selection.drop_reason).to eq(expected.fetch("dropped"))
          elsif expected.fetch("selection").values.all?(&:empty?)
            expect(selection).to be_nil
          else
            expect(selection).not_to be_dropped
            expect(selection.tags).to eq(expected.fetch("selection").fetch("tags"))
            expect(selection.key_patterns).to eq(expected.fetch("selection").fetch("keyPatterns"))
          end
        end
      end
    end

    it "accepts String keys" do
      selection = canonicalize("tags" => ["team:a"], "key_patterns" => ["checkout.*"])

      expect(selection.tags).to eq(["team:a"])
      expect(selection.key_patterns).to eq(["checkout.*"])
    end

    it "ignores unknown keys" do
      selection = canonicalize(tags: ["team:a"], keyPatterns: ["checkout.*"], extra: 1)

      expect(selection.tags).to eq(["team:a"])
      expect(selection.key_patterns).to eq([])
    end

    it "converts values in other encodings to UTF-8" do
      selection = canonicalize(tags: ["team:\u00E9".encode(Encoding::UTF_16LE), "team:a".b])

      expect(selection.tags).to eq(["team:a", "team:\u00E9"])
      expect(selection.tags.map(&:encoding)).to all(eq(Encoding::UTF_8))
    end

    it "keeps zero width characters and NUL, which are not Unicode White_Space" do
      selection = canonicalize(tags: ["\u200Ba", "\uFEFFb", "\u0000c", "\u3000d\u0085"])

      expect(selection.tags).to eq(["\u0000c", "d", "\u200Ba", "\uFEFFb"])
    end

    it "freezes the canonical selection" do
      selection = canonicalize(tags: [+"team:a"])

      expect(selection).to be_frozen
      expect(selection.tags).to be_frozen
      expect(selection.tags.first).to be_frozen
      expect(selection.key_patterns).to be_frozen
    end

    [nil, {}, {tags: nil, key_patterns: nil}, {tags: [], key_patterns: [" ", "\t"]}].each do |option|
      it "returns no selection for #{option.inspect}" do
        expect(canonicalize(option)).to be_nil
      end
    end

    malformed = {
      "a String option" => "team:a",
      "an Array option" => ["team:a"],
      "an Integer option" => 1,
      "a String list" => {tags: "team:a"},
      "a Hash list" => {key_patterns: {"a" => "b"}},
      "an Integer element" => {tags: [1]},
      "a nil element" => {tags: ["team:a", nil]},
      "a Symbol element" => {key_patterns: [:checkout]},
      "a UTF-8 String with invalid bytes" => {tags: [(+"team:\xFF").force_encoding(Encoding::UTF_8)]},
      "a binary String with non-ASCII bytes" => {tags: ["team:\u00E9".b]},
      "both spellings of one key" => {:tags => ["team:a"], "tags" => ["team:b"]},
      "a malformed key pattern list with too many tags" => {tags: Array.new(32) { |index| "t#{index}" }, key_patterns: [1]},
    }
    malformed.each do |description, option|
      it "drops #{description} as malformed_selection without raising" do
        selection = nil

        expect { selection = canonicalize(option) }.not_to raise_error
        expect(selection).to be_dropped
        expect(selection.drop_reason).to eq("malformed_selection")
      end
    end

    it "reports too_many_values before an over-long key pattern or tag" do
      selection = canonicalize(tags: Array.new(32) { |index| "t#{index}" }, key_patterns: ["a" * 201])

      expect(selection.drop_reason).to eq("too_many_values")
    end

    it "reports invalid_key_pattern before invalid_tag" do
      selection = canonicalize(tags: ["a" * 201], key_patterns: ["b" * 201])

      expect(selection.drop_reason).to eq("invalid_key_pattern")
    end

    it "measures value length in UTF-8 bytes" do
      expect(canonicalize(tags: ["\u00E9" * 100])).not_to be_dropped
      expect(canonicalize(tags: ["\u00E9" * 100 + "a"]).drop_reason).to eq("invalid_tag")
    end
  end

  describe "#==" do
    it "compares canonical lists" do
      expect(canonicalize(tags: [" b", "a", "a"])).to eq(canonicalize("tags" => ["a", "b"]))
      expect(canonicalize(tags: ["a"])).not_to eq(canonicalize(key_patterns: ["a"]))
      expect(canonicalize(tags: ["a"])).not_to eq(canonicalize(tags: ["b"]))
    end

    it "compares dropped selections by reason" do
      expect(canonicalize(tags: [1])).to eq(canonicalize(key_patterns: "a"))
      expect(canonicalize(tags: [1])).not_to eq(canonicalize(tags: ["a" * 201]))
    end
  end

  describe "#query" do
    it "repeats each parameter, tags first, in canonical order" do
      selection = canonicalize(key_patterns: ["checkout.*"], tags: ["team:b", "team:a"])

      expect(selection.query).to eq(
        "selected_flag_tags=team%3Aa&selected_flag_tags=team%3Ab&selected_flag_key_patterns=checkout.%2A",
      )
    end

    it "percent-encodes every byte outside the RFC 3986 unreserved set with uppercase hex" do
      selection = canonicalize(tags: ["a b+c~d-e_f.g!h'i(j)k*l%m&n=o/p?q#r\u00E9\u{1F600}"])

      expect(selection.query).to eq(
        "selected_flag_tags=a%20b%2Bc~d-e_f.g%21h%27i%28j%29k%2Al%25m%26n%3Do%2Fp%3Fq%23r%C3%A9%F0%9F%98%80",
      )
    end
  end
end
