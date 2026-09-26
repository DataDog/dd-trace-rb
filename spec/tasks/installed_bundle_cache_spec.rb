require "spec_helper"
require "tmpdir"
require_relative "../../tasks/installed_bundle_cache"

RSpec.describe InstalledBundleCache do
  subject(:cache) do
    described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["second.gemfile", "first.gemfile"],
      installed_path: temporary_directory.join("installed"),
    )
  end

  around do |example|
    Dir.mktmpdir do |directory|
      @temporary_directory = Pathname(directory)
      write("base.gemfile", "source \"https://rubygems.org\"\n")
      write("base.gemfile.lock", "base lock\n")
      write("first.gemfile", "eval_gemfile \"base.gemfile\"\n")
      write("first.gemfile.lock", "first lock\n")
      write("second.gemfile", "eval_gemfile \"base.gemfile\"\n")
      write("second.gemfile.lock", "second lock\n")
      example.run
    end
  end

  let(:temporary_directory) { @temporary_directory }

  def write(path, content)
    target = temporary_directory.join(path)
    target.dirname.mkpath
    target.write(content)
  end

  it "returns base and sorted appraisal Gemfiles" do
    expect(cache.gemfiles.map { |path| path.basename.to_s }).to eq(
      %w[base.gemfile first.gemfile second.gemfile]
    )
  end

  it "hashes lockfile paths and contents deterministically" do
    original = cache.lockfile_digest

    write("first.gemfile.lock", "changed lock\n")

    expect(cache.lockfile_digest).not_to eq(original)
  end

  it "uses schema, environment digest, and content digest in cache keys" do
    manifest = cache.to_h(cache_schema: "installed-test-v1-all-full", image_identity: "image-a")

    expect(manifest.fetch(:cache_key)).to eq(
      "installed-test-v1-all-full-#{manifest.fetch(:environment_digest)}-#{manifest.fetch(:content_digest)}"
    )
    expect(manifest.fetch(:restore_prefix)).to eq(
      "installed-test-v1-all-full-#{manifest.fetch(:environment_digest)}-"
    )
  end

  it "invalidates the environment digest when image identity changes" do
    first = cache.environment_digest(image_identity: "image-a")
    second = cache.environment_digest(image_identity: "image-b")

    expect(first).not_to eq(second)
  end

  it "invalidates the environment digest when native build flags change" do
    original = cache.environment_digest(image_identity: "image-a")
    changed = ClimateControl.modify("CFLAGS" => "-march=changed") do
      cache.environment_digest(image_identity: "image-a")
    end

    expect(changed).not_to eq(original)
  end

  it "invalidates the content digest when a Gemfile changes" do
    original = cache.content_digest

    write("first.gemfile", "eval_gemfile \"base.gemfile\"\ngem \"rake\"\n")

    expect(cache.content_digest).not_to eq(original)
  end

  it "invalidates the content digest when a lockfile changes" do
    original = cache.content_digest

    write("second.gemfile.lock", "changed lock\n")

    expect(cache.content_digest).not_to eq(original)
  end

  it "sorts content members by repository-relative path" do
    paths = cache.content.fetch("members").map { |member| member.fetch("path") }

    expect(paths).to eq(paths.sort)
  end

  it "identifies the base generation and omits base files for all-delta" do
    delta_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["second.gemfile", "first.gemfile"],
      strategy: "all-delta",
    )
    content = delta_cache.content(base_cache_key: "bundle-base-key")

    expect(content.fetch("base_cache_key")).to eq("bundle-base-key")
    expect(content.fetch("members").map { |member| member.fetch("path") }).not_to include(
      "base.gemfile",
      "base.gemfile.lock",
    )
  end

  it "requires a base cache key for all-delta" do
    delta_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: [],
      strategy: "all-delta",
    )

    expect { delta_cache.content_digest }.to raise_error(
      ArgumentError,
      "base_cache_key is required for all-delta strategy",
    )
  end

  it "extracts files changed since the base snapshot" do
    write("installed/gems/base.rb", "base\n")
    snapshot = temporary_directory.join("base-snapshot.json")
    cache.write_snapshot(snapshot)
    write("installed/gems/added.rb", "added\n")
    write("installed/gems/base.rb", "changed\n")

    destination = temporary_directory.join("delta")
    cache.extract_delta(base_snapshot_path: snapshot, destination: destination)

    expect(destination.join("gems/added.rb").read).to eq("added\n")
    expect(destination.join("gems/base.rb").read).to eq("changed\n")
  end

  it "does not extract unchanged base files" do
    write("installed/gems/base.rb", "base\n")
    snapshot = temporary_directory.join("base-snapshot.json")
    cache.write_snapshot(snapshot)

    destination = temporary_directory.join("delta")
    cache.extract_delta(base_snapshot_path: snapshot, destination: destination)

    expect(destination.join("gems/base.rb")).not_to exist
  end

  it "rejects missing lockfiles" do
    temporary_directory.join("first.gemfile.lock").delete

    expect { cache.lockfiles }.to raise_error("Lockfile not found: first.gemfile.lock")
  end
end
