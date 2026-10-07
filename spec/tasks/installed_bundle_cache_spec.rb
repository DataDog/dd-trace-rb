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

  it "invalidates the base and union keys when native build flags change" do
    original_base = cache.base_cache_key(image_identity: "image-a")
    changed_base = ClimateControl.modify("CFLAGS" => "-march=changed") do
      cache.base_cache_key(image_identity: "image-a")
    end

    expect(changed_base).not_to eq(original_base)
    expect(cache.cache_key(base_cache_key: changed_base)).not_to eq(
      cache.cache_key(base_cache_key: original_base)
    )
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

  it "includes paths in dependency identity" do
    write("renamed.gemfile", temporary_directory.join("first.gemfile").read)
    write("renamed.gemfile.lock", temporary_directory.join("first.gemfile.lock").read)
    renamed = build_cache(["base.gemfile", "renamed.gemfile", "second.gemfile"])

    expect(renamed.cache_key(base_cache_key: "base-a")).not_to eq(
      cache.cache_key(base_cache_key: "base-a")
    )
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

  it "reports failed appraisal installation" do
    allow(cache).to receive(:system).and_return(false)

    expect { cache.install_appraisals }.to raise_error("bundle install failed for first.gemfile")
  end

  it "reports failed bundle validation" do
    allow(cache).to receive(:system).and_return(false)

    expect { cache.check }.to raise_error("bundle check failed for base.gemfile")
  end
end
