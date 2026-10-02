require "spec_helper"
require "tmpdir"
require_relative "../../tasks/installed_bundle_cache"

RSpec.describe InstalledBundleCache do
  subject(:cache) do
    described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      matrix: matrix,
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
  let(:matrix) { instance_double(GithubMatrix, gemfiles: ["second.gemfile", "first.gemfile"]) }

  def write(path, content)
    target = temporary_directory.join(path)
    target.dirname.mkpath
    target.write(content)
  end

  it "returns the base and sorted appraisal Gemfiles" do
    expect(cache.gemfiles.map { |path| path.basename.to_s }).to eq(
      %w[base.gemfile first.gemfile second.gemfile]
    )
  end

  it "uses schema, environment digest, and content digest in the cache key" do
    manifest = cache.to_h(cache_schema: "installed-full-v1", image_identity: "image-a")

    expect(manifest.fetch(:cache_key)).to eq(
      "installed-full-v1-#{manifest.fetch(:environment_digest)}-#{manifest.fetch(:content_digest)}"
    )
  end

  it "invalidates the environment digest when image identity changes" do
    expect(cache.environment_digest(image_identity: "image-a")).not_to eq(
      cache.environment_digest(image_identity: "image-b")
    )
  end

  it "invalidates the environment digest when native build flags change" do
    original = cache.environment_digest(image_identity: "image-a")
    changed = ClimateControl.modify("CFLAGS" => "-march=changed") do
      cache.environment_digest(image_identity: "image-a")
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

    expect(cache.environment(image_identity: "image-a").fetch("bundler_settings")).to eq(
      "build.pg" => "--with-pg-config=/tmp/pg_config",
      "force_ruby_platform" => "true",
      "without" => "development",
    )
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
    paths = cache.content.map { |member| member.fetch("path") }

    expect(paths).to eq(paths.sort)
  end

  it "installs and checks every Gemfile" do
    commands = []
    allow(cache).to receive(:system) do |environment, command, *arguments|
      commands << [environment.fetch("BUNDLE_GEMFILE"), command, arguments]
      true
    end

    cache.install(jobs: 4)
    cache.check

    expect(commands.count { |_gemfile, _command, arguments| arguments == ["install", "--jobs", "4"] }).to eq(3)
    expect(commands.count { |_gemfile, _command, arguments| arguments == ["check"] }).to eq(3)
  end

  it "rejects missing lockfiles" do
    temporary_directory.join("first.gemfile.lock").delete

    expect { cache.content }.to raise_error("Lockfile not found: first.gemfile.lock")
  end
end
