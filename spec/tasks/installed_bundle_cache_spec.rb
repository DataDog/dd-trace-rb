require "spec_helper"
require "tmpdir"
require_relative "../../tasks/installed_bundle_cache"

RSpec.describe InstalledBundleCache do
  subject(:cache) { build_cache(["second.gemfile", "base.gemfile", "first.gemfile"]) }

  around do |example|
    Dir.mktmpdir do |directory|
      @temporary_directory = Pathname(directory)
      Dir.chdir(directory) do
        write("base.gemfile", "source \"https://rubygems.org\"\n")
        write("base.gemfile.lock", "base lock\n")
        write("first.gemfile", "eval_gemfile \"base.gemfile\"\n")
        write("first.gemfile.lock", "first lock\n")
        write("second.gemfile", "eval_gemfile \"base.gemfile\"\n")
        write("second.gemfile.lock", "second lock\n")
        described_class::CACHE_RECIPE_FILES.each { |path| write(path, "recipe: #{path}\n") }
        example.run
      end
    end
  end

  let(:temporary_directory) { @temporary_directory }

  def build_cache(gemfiles)
    described_class.new(base_gemfile: "base.gemfile", gemfiles: gemfiles)
  end

  def write(path, content)
    target = temporary_directory.join(path)
    target.dirname.mkpath
    target.write(content)
  end

  it "uses versioned base and union cache keys" do
    base_key = cache.base_cache_key(image_identity: "image-a")

    expect(base_key).to start_with("bundle-base-v1-")
    expect(cache.cache_key(base_cache_key: base_key)).to start_with("bundle-installed-matrix-v3-")
  end

  it "produces the same union key regardless of applicable Gemfile order" do
    reordered = build_cache(["first.gemfile", "base.gemfile", "second.gemfile"])

    expect(reordered.cache_key(base_cache_key: "base-a")).to eq(
      cache.cache_key(base_cache_key: "base-a")
    )
  end

  it "invalidates the base and union keys when image identity changes" do
    original_base = cache.base_cache_key(image_identity: "image-a")
    changed_base = cache.base_cache_key(image_identity: "image-b")

    expect(changed_base).not_to eq(original_base)
    expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(
      cache.cache_key(base_cache_key: original_base)
    )
  end

  it "invalidates the union key when the base cache key changes" do
    expect(cache.cache_key(base_cache_key: "base-a")).not_to eq(
      cache.cache_key(base_cache_key: "base-b")
    )
  end

  %w[
    .github/actions/bundle-cache/action.yml
    .github/actions/installed-bundle-cache/action.yml
    tasks/github.rake
    tasks/installed_bundle_cache.rb
  ].each do |path|
    it "invalidates the base and union keys when #{path} changes" do
      original_base = cache.base_cache_key(image_identity: "image-a")
      original_union = cache.cache_key(base_cache_key: original_base)

      write(path, "changed recipe\n")
      changed_base = cache.base_cache_key(image_identity: "image-a")

      expect(changed_base).not_to eq(original_base)
      expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(original_union)
    end
  end

  %w[ARCHFLAGS CFLAGS CPPFLAGS CXXFLAGS LDFLAGS MAKEFLAGS].each do |flag|
    it "invalidates the base and union keys when #{flag} changes" do
      original_base = cache.base_cache_key(image_identity: "image-a")
      changed_base = ClimateControl.modify(flag => "changed") do
        cache.base_cache_key(image_identity: "image-a")
      end

      expect(changed_base).not_to eq(original_base)
      expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(
        cache.cache_key(base_cache_key: original_base)
      )
    end
  end

  %w[force_ruby_platform only with without build.pg].each do |key|
    it "invalidates the base and union keys when Bundler #{key} changes" do
      values = {key => "original"}
      settings = instance_double(Bundler::Settings, all: values.keys)
      allow(settings).to receive(:[]) { |setting| values.fetch(setting) }
      allow(Bundler).to receive(:settings).and_return(settings)
      original_base = cache.base_cache_key(image_identity: "image-a")
      values[key] = "changed"
      changed_base = cache.base_cache_key(image_identity: "image-a")

      expect(changed_base).not_to eq(original_base)
      expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(
        cache.cache_key(base_cache_key: original_base)
      )
    end
  end

  it "hashes only Bundler settings that can change installed contents" do
    values = {
      "build.pg" => "--with-pg-config=/tmp/pg_config",
      "cache_path" => "tmp/cache",
      "force_ruby_platform" => "true",
      "frozen" => "true",
      "without" => "development",
    }
    settings = instance_double(Bundler::Settings, all: values.keys)
    allow(settings).to receive(:[]) { |key| values.fetch(key) }
    allow(Bundler).to receive(:settings).and_return(settings)

    original = cache.base_cache_key(image_identity: "image-a")
    values["cache_path"] = "other/cache"
    values["frozen"] = "false"
    expect(cache.base_cache_key(image_identity: "image-a")).to eq(original)

    values["without"] = "test"
    expect(cache.base_cache_key(image_identity: "image-a")).not_to eq(original)
  end

  it "invalidates the base and union keys when the base Gemfile changes" do
    original_base = cache.base_cache_key(image_identity: "image-a")
    original_union = cache.cache_key(base_cache_key: original_base)

    write("base.gemfile", "source \"https://rubygems.org\"\ngem \"rake\"\n")
    changed_base = cache.base_cache_key(image_identity: "image-a")

    expect(changed_base).not_to eq(original_base)
    expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(original_union)
  end

  it "invalidates the union key when an appraisal Gemfile changes" do
    original = cache.cache_key(base_cache_key: "base-a")

    write("first.gemfile", "eval_gemfile \"base.gemfile\"\ngem \"rake\"\n")

    expect(cache.cache_key(base_cache_key: "base-a")).not_to eq(original)
  end

  it "invalidates the union key when an appraisal lockfile changes" do
    original = cache.cache_key(base_cache_key: "base-a")

    write("second.gemfile.lock", "changed lock\n")

    expect(cache.cache_key(base_cache_key: "base-a")).not_to eq(original)
  end

  it "distinguishes Gemfile content from lockfile content" do
    gemfile_content = temporary_directory.join("first.gemfile").read
    lockfile_content = temporary_directory.join("first.gemfile.lock").read
    original = cache.cache_key(base_cache_key: "base-a")

    write("first.gemfile", lockfile_content)
    write("first.gemfile.lock", gemfile_content)

    expect(cache.cache_key(base_cache_key: "base-a")).not_to eq(original)
  end

  it "excludes paths from dependency identity" do
    write("renamed.gemfile", temporary_directory.join("first.gemfile").read)
    write("renamed.gemfile.lock", temporary_directory.join("first.gemfile.lock").read)
    renamed = build_cache(["base.gemfile", "renamed.gemfile", "second.gemfile"])

    expect(renamed.cache_key(base_cache_key: "base-a")).to eq(
      cache.cache_key(base_cache_key: "base-a")
    )
  end

  it "excludes the base Gemfile path from base identity" do
    write("renamed.gemfile", temporary_directory.join("base.gemfile").read)
    write("renamed.gemfile.lock", temporary_directory.join("base.gemfile.lock").read)
    renamed = described_class.new(base_gemfile: "renamed.gemfile")

    expect(renamed.base_cache_key(image_identity: "image-a")).to eq(
      cache.base_cache_key(image_identity: "image-a")
    )
  end

  it "deduplicates identical dependency content" do
    write("duplicate.gemfile", temporary_directory.join("first.gemfile").read)
    write("duplicate.gemfile.lock", temporary_directory.join("first.gemfile.lock").read)
    duplicated = build_cache(["base.gemfile", "first.gemfile", "duplicate.gemfile", "second.gemfile"])

    expect(duplicated.cache_key(base_cache_key: "base-a")).to eq(
      cache.cache_key(base_cache_key: "base-a")
    )
  end

  it "invalidates the base and union keys when the base lockfile changes" do
    original_base = cache.base_cache_key(image_identity: "image-a")
    original_union = cache.cache_key(base_cache_key: original_base)

    write("base.gemfile.lock", "changed lock\n")
    changed_base = cache.base_cache_key(image_identity: "image-a")

    expect(changed_base).not_to eq(original_base)
    expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(original_union)
  end

  it "rejects missing base and appraisal lockfiles" do
    temporary_directory.join("base.gemfile.lock").delete
    expect { cache.base_cache_key(image_identity: "image-a") }.to raise_error(
      "Lockfile not found: base.gemfile.lock"
    )

    write("base.gemfile.lock", "base lock\n")
    temporary_directory.join("first.gemfile.lock").delete
    expect { cache.cache_key(base_cache_key: "base-a") }.to raise_error(
      "Lockfile not found: first.gemfile.lock"
    )
  end
end
