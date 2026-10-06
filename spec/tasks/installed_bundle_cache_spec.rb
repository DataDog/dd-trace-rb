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
        example.run
      end
    end
  end

  let(:temporary_directory) { @temporary_directory }

  def build_cache(gemfiles)
    allow(GithubMatrix).to receive(:new).and_return(instance_double(GithubMatrix, gemfiles: gemfiles))
    described_class.new(base_gemfile: "base.gemfile")
  end

  def write(path, content)
    target = temporary_directory.join(path)
    target.dirname.mkpath
    target.write(content)
  end

  it "returns the base and sorted applicable Gemfiles once" do
    expect(cache.gemfiles.map { |path| File.basename(path) }).to eq(
      %w[base.gemfile first.gemfile second.gemfile]
    )
  end

  it "excludes the fallback base Gemfile from appraisal Gemfiles" do
    expect(cache.appraisal_gemfiles.map { |path| File.basename(path) }).to eq(
      %w[first.gemfile second.gemfile]
    )
  end

  it "uses the cache format and identity digest in the cache key" do
    expect(cache.cache_key(image_identity: "image-a", base_cache_key: "base-a")).to eq(
      "bundle-installed-matrix-v3-#{cache.identity_digest(image_identity: "image-a", base_cache_key: "base-a")}"
    )
  end

  it "produces a deterministic identity regardless of applicable Gemfile order" do
    reordered = build_cache(["first.gemfile", "base.gemfile", "second.gemfile"])

    expect(reordered.identity_digest(image_identity: "image-a", base_cache_key: "base-a")).to eq(
      cache.identity_digest(image_identity: "image-a", base_cache_key: "base-a")
    )
  end

  it "invalidates the identity when image identity changes" do
    expect(cache.identity_digest(image_identity: "image-a", base_cache_key: "base-a")).not_to eq(
      cache.identity_digest(image_identity: "image-b", base_cache_key: "base-a")
    )
  end

  it "invalidates the identity and key when the base cache identity changes" do
    expect(cache.identity_digest(image_identity: "image-a", base_cache_key: "base-a")).not_to eq(
      cache.identity_digest(image_identity: "image-a", base_cache_key: "base-b")
    )
    expect(cache.cache_key(image_identity: "image-a", base_cache_key: "base-a")).not_to eq(
      cache.cache_key(image_identity: "image-a", base_cache_key: "base-b")
    )
  end

  it "invalidates the identity when native build flags change" do
    original = cache.identity_digest(image_identity: "image-a", base_cache_key: "base-a")
    changed = ClimateControl.modify("CFLAGS" => "-march=changed") do
      cache.identity_digest(image_identity: "image-a", base_cache_key: "base-a")
    end

    expect(changed).not_to eq(original)
  end

  it "hashes only Bundler settings that can change installed contents" do
    settings = instance_double(
      Bundler::Settings,
      all: %w[build.pg cache_path force_ruby_platform frozen without],
    )
    allow(settings).to receive(:[]).with("build.pg").and_return("--with-pg-config=/tmp/pg_config")
    allow(settings).to receive(:[]).with("force_ruby_platform").and_return("true")
    allow(settings).to receive(:[]).with("without").and_return("development")
    allow(Bundler).to receive(:settings).and_return(settings)

    expect(
      cache.identity(image_identity: "image-a", base_cache_key: "base-a").fetch("bundler_settings")
    ).to eq(
      "build.pg" => "--with-pg-config=/tmp/pg_config",
      "force_ruby_platform" => "true",
      "without" => "development",
    )
  end

  it "invalidates the content identity when a Gemfile changes" do
    original = cache.content

    write("first.gemfile", "eval_gemfile \"base.gemfile\"\ngem \"rake\"\n")

    expect(cache.content).not_to eq(original)
  end

  it "invalidates the content identity when a lockfile changes" do
    original = cache.content

    write("second.gemfile.lock", "changed lock\n")

    expect(cache.content).not_to eq(original)
  end

  it "distinguishes Gemfile content from lockfile content" do
    gemfile_content = temporary_directory.join("first.gemfile").read
    lockfile_content = temporary_directory.join("first.gemfile.lock").read
    original = cache.content

    write("first.gemfile", lockfile_content)
    write("first.gemfile.lock", gemfile_content)

    expect(cache.content).not_to eq(original)
  end

  it "does not include paths in content identity" do
    write("renamed.gemfile", temporary_directory.join("first.gemfile").read)
    write("renamed.gemfile.lock", temporary_directory.join("first.gemfile.lock").read)
    renamed = build_cache(["base.gemfile", "renamed.gemfile", "second.gemfile"])

    expect(renamed.content).to eq(cache.content)
  end

  it "sorts content hashes" do
    expect(cache.content).to eq(cache.content.sort)
  end

  it "installs each appraisal and checks every Gemfile" do
    commands = []
    allow(cache).to receive(:system) do |environment, command, *arguments|
      commands << [environment.fetch("BUNDLE_GEMFILE"), command, arguments]
      true
    end

    cache.install_appraisals
    cache.check

    installed = commands.select { |_gemfile, _command, arguments| arguments == ["install"] }
    expect(installed.map { |gemfile, _command, _arguments| File.basename(gemfile) }).to contain_exactly(
      "first.gemfile",
      "second.gemfile",
    )
    expect(commands.count { |_gemfile, _command, arguments| arguments == ["check"] }).to eq(3)
  end

  it "rejects missing lockfiles" do
    temporary_directory.join("first.gemfile.lock").delete

    expect { cache.content }.to raise_error("Lockfile not found: first.gemfile.lock")
  end

  it "reports failed appraisal installation" do
    allow(cache).to receive(:system).and_return(false)

    expect { cache.install_appraisals }.to raise_error("bundle install failed for first.gemfile")
  end

  it "reports failed bundle validation" do
    allow(cache).to receive(:system).and_return(false)

    expect { cache.check }.to raise_error("bundle check failed for base.gemfile")
  end
end
