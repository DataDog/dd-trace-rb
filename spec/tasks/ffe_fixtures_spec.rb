# frozen_string_literal: true

require "stringio"
require "zlib"
require "rubygems/package"
require "spec_helper"
require_relative "../../tasks/lib/fixtures/ffe"

# These tests stub every HTTP call, so they never contact GitHub.
RSpec.describe FfeFixtures do
  around do |example|
    Dir.mktmpdir("ffe-fixtures-spec-") do |temporary|
      @temporary = temporary
      example.run
    end
  end

  let(:repository) { File.join(@temporary, "repository") }
  let(:commit) { "a" * 40 }
  let(:config) { '{"flags":{}}' }
  let(:cases) { '[{"flag":"test"}]' }
  let(:files_by_path) { {"ufc-config.json" => config, "evaluation-cases/cases.json" => cases} }

  def tarball_url_for(sha)
    "https://codeload.github.com/DataDog/ffe-system-test-data/tar.gz/#{sha}"
  end

  def tarball(files_by_path, sha)
    tar_io = StringIO.new
    Gem::Package::TarWriter.new(tar_io) do |tar|
      files_by_path.each do |path, contents|
        tar.add_file("ffe-system-test-data-#{sha}/#{path}", 0o644) { |file| file.write(contents) }
      end
    end
    gzip_io = StringIO.new
    Zlib::GzipWriter.wrap(gzip_io) { |gzip| gzip.write(tar_io.string) }
    gzip_io.string
  end

  # Maps each upstream commit to the file contents its tarball serves.
  def stub_upstream(files_by_sha)
    allow_any_instance_of(described_class).to receive(:http_get) do |_fetcher, url, **_kwargs|
      match = url.match(%r{\Ahttps://codeload\.github\.com/DataDog/ffe-system-test-data/tar\.gz/([0-9a-f]{40})\z})
      raise "Unexpected URL: #{url}" unless match

      tarball(files_by_sha.fetch(match[1]), match[1])
    end
  end

  before do
    stub_const("FfeFixtures::COMMIT_SHA", commit)
  end

  describe ".download" do
    it "pins a full upstream commit" do
      pin = File.read(File.expand_path("../../tasks/lib/fixtures/ffe/version", __dir__))

      expect(pin).to match(/\A[0-9a-f]{40}\n\z/)
    end

    it "downloads the pinned corpus into the SHA-keyed cache" do
      stub_upstream(commit => files_by_path)

      root = described_class.download(repository)

      expect(File.read(File.join(root, "ufc-config.json"))).to eq(config)
      expect(File.read(File.join(root, "evaluation-cases", "cases.json"))).to eq(cases)
    end

    it "does not contact the network once the corpus is cached" do
      stub_upstream(commit => files_by_path)
      described_class.download(repository)

      expect_any_instance_of(described_class).not_to receive(:http_get)

      root = described_class.download(repository)
      expect(File.directory?(root)).to be(true)
    end

    it "copies only the configuration and flat evaluation cases, skipping the rest of the tarball" do
      stub_upstream(
        commit => files_by_path.merge(
          "README.md" => "documentation",
          "ci/lint.yml" => "jobs",
          "evaluation-cases/nested/case.json" => "[]",
          "evaluation-cases/notes.txt" => "not a case",
        )
      )

      root = described_class.download(repository)

      expect(Dir.children(root).sort).to eq(["evaluation-cases", "ufc-config.json"])
      expect(Dir.children(File.join(root, "evaluation-cases"))).to eq(["cases.json"])
    end

    it "rejects a corpus without the configuration or cases, without leaving a cache entry" do
      stub_upstream(commit => {"README.md" => "documentation"})

      expect { described_class.download(repository) }.to raise_error(/No FFE fixtures found/)
      expect(File.directory?(File.join(repository, described_class::CACHE, commit))).to be(false)
    end
  end

  describe "#http_get retries" do
    it "retries a transient failure and succeeds" do
      calls = 0
      allow_any_instance_of(described_class).to receive(:http_attempt) do |_fetcher, url, **_kwargs|
        calls += 1
        (calls == 1) ? raise(described_class::TransientHTTPError, "transient") : "body"
      end
      allow_any_instance_of(described_class).to receive(:sleep)

      fetcher = described_class.new(repository, commit)

      expect(fetcher.send(:http_get, tarball_url_for(commit))).to eq("body")
      expect(calls).to eq(2)
    end

    it "gives up after the attempt budget and keeps the last error" do
      allow_any_instance_of(described_class)
        .to receive(:http_attempt).and_raise(Net::OpenTimeout, "timed out")
      expect_any_instance_of(described_class).to receive(:sleep).twice

      fetcher = described_class.new(repository, commit)

      expect { fetcher.send(:http_get, tarball_url_for(commit)) }
        .to raise_error(Net::OpenTimeout, /timed out/)
    end
  end
end
