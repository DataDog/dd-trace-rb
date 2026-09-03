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

    it "raises when a required field is missing" do
      path = write_fragment("1.json", valid_entry.reject { |k, _| k == "message" })

      expect { described_class.read(path) }
        .to raise_error(ReleasePrep::ValidationError, /message/)
    end

    it "raises when type is not in the closed enum" do
      path = write_fragment("1.json", valid_entry("type" => "Removed"))

      expect { described_class.read(path) }
        .to raise_error(ReleasePrep::ValidationError, /type/)
    end

    it "raises when prefix is not in the closed enum" do
      path = write_fragment("1.json", valid_entry("prefix" => "Redis"))

      expect { described_class.read(path) }
        .to raise_error(ReleasePrep::ValidationError, /prefix/)
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
