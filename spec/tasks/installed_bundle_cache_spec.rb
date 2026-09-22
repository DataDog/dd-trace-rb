require "spec_helper"
require "tmpdir"
require_relative "../../tasks/installed_bundle_cache"

RSpec.describe InstalledBundleCache do
  subject(:cache) do
    described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["second.gemfile", "first.gemfile"],
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
    temporary_directory.join(path).write(content)
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

  it "includes image identity and lockfiles in exact cache keys" do
    first_key = cache.cache_key(cache_schema: "installed-test-v1", image_identity: "image-a")
    second_key = cache.cache_key(cache_schema: "installed-test-v1", image_identity: "image-b")
    write("second.gemfile.lock", "changed lock\n")
    changed_lock_key = cache.cache_key(cache_schema: "installed-test-v1", image_identity: "image-a")

    expect(first_key).not_to eq(second_key)
    expect(first_key).not_to eq(changed_lock_key)
    expect(first_key).to start_with("installed-test-v1-")
  end

  it "invalidates the cache key when native build flags change" do
    original = cache.cache_key(cache_schema: "installed-test-v1", image_identity: "image-a")
    changed = ClimateControl.modify("CFLAGS" => "-march=changed") do
      cache.cache_key(cache_schema: "installed-test-v1", image_identity: "image-a")
    end

    expect(changed).not_to eq(original)
  end

  it "rejects missing lockfiles" do
    temporary_directory.join("first.gemfile.lock").delete

    expect { cache.lockfiles }.to raise_error("Lockfile not found: first.gemfile.lock")
  end
end
