require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../tasks/package_cache_archive"

RSpec.describe PackageCacheArchive do
  around do |example|
    Dir.mktmpdir do |directory|
      @directory = directory
      example.run
    end
  end

  let(:manifest) do
    {
      "appraisal_gemfiles" => ["gemfiles/example.gemfile"],
      "packages" => [{"name" => "excon", "version" => "1.7.1", "platform" => "ruby"}],
      "package_filenames" => ["excon-1.7.1.gem"],
      "package_downloads" => [
        {"filename" => "excon-1.7.1.gem", "source_uri" => "https://rubygems.org/"},
      ],
      "git_sources" => [],
    }
  end

  it "downloads missing package archives without installing the bundle" do
    calls = []
    archive = described_class.new(
      path: @directory,
      manifest: manifest,
      package_downloader: lambda { |spec, source, destination| calls << [spec, source, destination] },
    )

    archive.populate

    expect(calls.length).to eq(1)
    expect(calls.first[0]).to have_attributes(name: "excon", version: Gem::Version.new("1.7.1"), platform: Gem::Platform::RUBY)
    expect(calls.first[1]).to eq("https://rubygems.org/")
    expect(calls.first[2]).to eq(Pathname(@directory))
  end

  it "caches Git sources with frozen package-cache settings" do
    calls = []
    manifest["git_sources"] = [
      {
        "uri" => "https://github.com/DataDog/rails",
        "revision" => "592dfae8747db3bb28c3292a9730817f0fa76885",
        "gemfiles" => ["gemfiles/example.gemfile", "gemfiles/unused.gemfile"],
      },
    ]
    archive = described_class.new(
      path: @directory,
      manifest: manifest,
      command_runner: lambda { |env, command| calls << [env, command] },
      package_downloader: lambda { |spec, _source, destination| FileUtils.touch(destination.join(spec.file_name)) },
    )

    archive.populate

    expect(calls).to contain_exactly([
      hash_including(
        "BUNDLE_GEMFILE" => File.expand_path("gemfiles/example.gemfile"),
        "BUNDLE_CACHE_PATH" => @directory,
        "BUNDLE_CACHE_ALL" => "true",
        "BUNDLE_NO_PRUNE" => "true",
        "BUNDLE_FROZEN" => "true",
      ),
      ["bundle", "cache", "--no-install"],
    ])
  end

  it "does not recache a complete Git source" do
    manifest["git_sources"] = [
      {
        "uri" => "https://github.com/DataDog/rails",
        "revision" => "592dfae8747db3bb28c3292a9730817f0fa76885",
        "gemfiles" => ["gemfiles/example.gemfile"],
      },
    ]
    FileUtils.mkdir_p(File.join(@directory, "rails-592dfae8747d"))
    FileUtils.touch(File.join(@directory, "rails-592dfae8747d", ".bundlecache"))
    calls = []
    archive = described_class.new(
      path: @directory,
      manifest: manifest,
      command_runner: lambda { |env, command| calls << [env, command] },
      package_downloader: lambda { |spec, _source, destination| FileUtils.touch(destination.join(spec.file_name)) },
    )

    archive.populate

    expect(calls).to be_empty
  end

  it "rejects a partial Git source" do
    manifest["git_sources"] = [
      {
        "uri" => "https://github.com/DataDog/rails",
        "revision" => "592dfae8747db3bb28c3292a9730817f0fa76885",
        "gemfiles" => ["gemfiles/example.gemfile"],
      },
    ]
    FileUtils.touch(File.join(@directory, "excon-1.7.1.gem"))
    FileUtils.mkdir_p(File.join(@directory, "rails-592dfae8747d", ".git"))
    archive = described_class.new(path: @directory, manifest: manifest)

    expect { archive.validate! }.to raise_error(RuntimeError, /592dfae8747db3bb28c3292a9730817f0fa76885/)
  end

  it "prunes packages outside the manifest" do
    FileUtils.touch(File.join(@directory, "excon-1.7.1.gem"))
    FileUtils.touch(File.join(@directory, "logger-1.7.0.gem"))
    FileUtils.mkdir_p(File.join(@directory, "old-source-123456789012"))
    archive = described_class.new(path: @directory, manifest: manifest)

    archive.prune

    expect(Dir.children(@directory)).to eq(["excon-1.7.1.gem"])
  end

  it "rejects an incomplete package archive" do
    archive = described_class.new(path: @directory, manifest: manifest)

    expect { archive.validate! }.to raise_error(RuntimeError, /excon-1\.7\.1\.gem/)
  end

  it "reports package count and bytes including hidden Git-source files" do
    File.binwrite(File.join(@directory, "excon-1.7.1.gem"), "gem")
    FileUtils.mkdir_p(File.join(@directory, "source"))
    File.binwrite(File.join(@directory, "source", ".bundlecache"), "cache")
    archive = described_class.new(path: @directory, manifest: manifest)

    expect(archive.statistics).to eq("file_count" => 2, "byte_count" => 8)
  end
end
