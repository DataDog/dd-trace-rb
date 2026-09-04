# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../tasks/release_prep/fragment"

RSpec.describe ReleasePrep::Fragment do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write_fragment(name, entry)
    path = File.join(@dir, name)
    File.write(path, entry.to_json)
    path
  end

  def valid_entry(overrides = {})
    {
      "type" => "Fixed",
      "prefix" => "Tracing",
      "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/6300",
      "message" => "Fix a bug.",
    }.merge(overrides)
  end

  describe ".read" do
    it "exposes the fragment's fields" do
      path = write_fragment("1.json", valid_entry.merge("author" => "octocat"))

      fragment = described_class.read(path)

      expect(fragment.path).to eq(path)
      expect(fragment.type).to eq("Fixed")
      expect(fragment.prefix).to eq("Tracing")
      expect(fragment.pull_request).to eq("https://github.com/DataDog/dd-trace-rb/pull/6300")
      expect(fragment.pr_number).to eq("6300")
      expect(fragment.message).to eq("Fix a bug.")
      expect(fragment.author).to eq("octocat")
    end

    it "leaves author nil when absent" do
      fragment = described_class.read(write_fragment("1.json", valid_entry))

      expect(fragment.author).to be_nil
    end

    it "raises on invalid JSON, naming the file" do
      path = File.join(@dir, "bad.json")
      File.write(path, "{not json")

      expect { described_class.read(path) }
        .to raise_error(ReleasePrep::ValidationError, /bad\.json/)
    end

    it "reads a fragment with content violations without raising" do
      path = write_fragment("1.json", valid_entry("type" => "Removed"))

      expect { described_class.read(path) }.not_to raise_error
    end
  end

  describe "#errors" do
    it "is empty for a valid fragment" do
      fragment = described_class.read(write_fragment("1.json", valid_entry))

      expect(fragment.errors).to eq([])
    end

    it "reports a missing required field, naming the field and file" do
      path = write_fragment("1.json", valid_entry.reject { |k, _| k == "message" })

      expect(described_class.read(path).errors)
        .to contain_exactly(/1\.json: missing required field "message"/)
    end

    it "reports a type outside the closed enum" do
      path = write_fragment("1.json", valid_entry("type" => "Removed"))

      expect(described_class.read(path).errors).to contain_exactly(/type "Removed" must be one of/)
    end

    it "reports a prefix outside the closed enum" do
      path = write_fragment("1.json", valid_entry("prefix" => "Redis"))

      expect(described_class.read(path).errors).to contain_exactly(/prefix "Redis" must be one of/)
    end

    it "collects every violation at once" do
      path = write_fragment("1.json", valid_entry("type" => "Removed", "prefix" => "Redis"))

      expect(described_class.read(path).errors).to contain_exactly(
        /type "Removed" must be one of/,
        /prefix "Redis" must be one of/,
      )
    end

    it "reports a pull_request that is not a well-formed dd-trace-rb PR URL" do
      path = write_fragment("1.json", valid_entry("pull_request" => "https://github.com/other/rb/pull/1"))

      expect(described_class.read(path).errors).to contain_exactly(%r{pull_request .*other/rb})
    end

    it "reports a message over the length cap, naming the actual length" do
      path = write_fragment("1.json", valid_entry("message" => "Fix a bug." + "a" * 237))

      expect(described_class.read(path).errors).to contain_exactly(/message is 247 characters, cap is 240/)
    end

    it "accepts a message at the cap" do
      path = write_fragment("1.json", valid_entry("message" => "F" + "a" * 239))

      expect(described_class.read(path).errors).to eq([])
    end
  end

  describe "#to_s" do
    it "renders the prefix, message, and PR number" do
      fragment = described_class.read(write_fragment("1.json", valid_entry))

      expect(fragment.to_s).to eq("* Tracing: Fix a bug. (#6300)")
    end

    it "renders the author credit when present" do
      fragment = described_class.read(write_fragment("1.json", valid_entry.merge("author" => "octocat")))

      expect(fragment.to_s).to eq("* Tracing: Fix a bug. (#6300) (@octocat)")
    end
  end

  describe "#delete!" do
    it "deletes the fragment's file" do
      path = write_fragment("1.json", valid_entry)
      fragment = described_class.read(path)

      fragment.delete!

      expect(File.exist?(path)).to be(false)
    end
  end
end
