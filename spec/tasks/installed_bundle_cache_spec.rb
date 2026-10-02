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
      group: "standard-0",
    )
  end

  around do |example|
    Dir.mktmpdir do |directory|
      @temporary_directory = Pathname(directory)
      write("base.gemfile", "source \"https://rubygems.org\"\n")
      write("base.gemfile.lock", lockfile("base (1.0.0)"))
      write("first.gemfile", "eval_gemfile \"base.gemfile\"\n")
      write("first.gemfile.lock", lockfile("base (1.0.0)", "first (2.0.0)"))
      write("second.gemfile", "eval_gemfile \"base.gemfile\"\n")
      write("second.gemfile.lock", lockfile("base (1.0.0)", "second (3.0.0)"))
      example.run
    end
  end

  let(:temporary_directory) { @temporary_directory }

  def write(path, content)
    target = temporary_directory.join(path)
    target.dirname.mkpath
    target.write(content)
  end

  def lockfile(*specs)
    <<~LOCK
      GEM
        remote: https://rubygems.org/
        specs:
      #{specs.sort.map { |spec| "    #{spec}" }.join("\n")}

      PLATFORMS
        ruby

      DEPENDENCIES
      #{specs.map { |spec| "  #{spec.split.first}" }.uniq.sort.join("\n")}

      BUNDLED WITH
         2.6.9
    LOCK
  end

  it "uses schema, environment digest, and content digest in cache keys" do
    manifest = cache.to_h(
      cache_schema: "installed-partition-v1-standard-0",
      image_identity: "image-a",
      base_cache_key: "base-key",
    )

    expect(manifest.fetch(:cache_key)).to eq(
      "installed-partition-v1-standard-0-#{manifest.fetch(:environment_digest)}-#{manifest.fetch(:content_digest)}"
    )
  end

  it "invalidates environment identity for image and native build changes" do
    original = cache.environment_digest(image_identity: "image-a")
    changed_flags = ClimateControl.modify("CFLAGS" => "-march=changed") do
      cache.environment_digest(image_identity: "image-a")
    end

    expect(cache.environment_digest(image_identity: "image-b")).not_to eq(original)
    expect(changed_flags).not_to eq(original)
  end

  it "keeps only installed-content Bundler settings in environment identity" do
    expect(described_class::BUNDLER_SETTING_KEYS).to contain_exactly(
      "force_ruby_platform",
      "only",
      "with",
      "without",
    )
  end

  it "hashes appraisal Gemfiles, lockfiles, and base generation" do
    content = cache.content(base_cache_key: "base-key")

    expect(content.fetch("base_cache_key")).to eq("base-key")
    expect(content.fetch("members").map { |member| member.fetch("path") }).to eq(
      %w[first.gemfile first.gemfile.lock second.gemfile second.gemfile.lock]
    )
  end

  it "does not hash task or batch metadata" do
    other = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile", "second.gemfile"],
      installed_path: temporary_directory.join("installed"),
      group: "renamed-batch",
    )

    expect(other.content_digest(base_cache_key: "base-key")).to eq(
      cache.content_digest(base_cache_key: "base-key")
    )
  end

  it "invalidates content identity when an appraisal or base generation changes" do
    original = cache.content_digest(base_cache_key: "base-key")
    write("first.gemfile.lock", lockfile("base (1.0.0)", "first (2.1.0)"))

    expect(cache.content_digest(base_cache_key: "base-key")).not_to eq(original)
    expect(cache.content_digest(base_cache_key: "other-base-key")).not_to eq(original)
  end

  it "requires a base cache key" do
    expect { cache.content_digest(base_cache_key: nil) }.to raise_error(
      ArgumentError,
      "base_cache_key is required",
    )
  end

  it "maps group-only specs to direct installed cache paths" do
    expect(cache.cache_paths).to contain_exactly(
      temporary_directory.join("installed/gems/first-2.0.0").to_s,
      temporary_directory.join("installed/specifications/first-2.0.0.gemspec").to_s,
      temporary_directory.join(
        "installed/extensions/#{Gem::Platform.local}/#{Gem.extension_api_version}/first-2.0.0"
      ).to_s,
      temporary_directory.join("installed/gems/second-3.0.0").to_s,
      temporary_directory.join("installed/specifications/second-3.0.0.gemspec").to_s,
      temporary_directory.join(
        "installed/extensions/#{Gem::Platform.local}/#{Gem.extension_api_version}/second-3.0.0"
      ).to_s,
      temporary_directory.join("installed/bin").to_s,
    )
  end

  it "omits a locally compatible package supplied by base" do
    write("base.gemfile.lock", lockfile("group (2.0.0)"))
    write("first.gemfile.lock", lockfile("group (2.0.0-x86_64-linux)"))
    allow(Gem::Platform).to receive(:local).and_return(Gem::Platform.new("x86_64-linux"))
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      installed_path: temporary_directory.join("installed"),
      group: "standard-0",
    )

    expect(grouped_cache.cache_paths).to be_empty
  end

  it "selects the best native platform variant" do
    write(
      "first.gemfile.lock",
      lockfile(
        "base (1.0.0)",
        "group (2.0.0-x86_64-linux-gnu)",
        "group (2.0.0-x86_64-linux-musl)",
      ),
    )
    allow(Gem::Platform).to receive(:local).and_return(Gem::Platform.new("x86_64-linux"))
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      installed_path: temporary_directory.join("installed"),
      group: "standard-0",
    )

    expect(grouped_cache.cache_paths).to include(
      temporary_directory.join("installed/gems/group-2.0.0-x86_64-linux-gnu").to_s
    )
  end

  it "omits default gems and memoizes their identities" do
    default_specification = Gem::Specification.new do |spec|
      spec.name = "first"
      spec.version = "2.0.0"
    end
    default_specification.loaded_from = File.join(Gem.default_dir, "specifications/first-2.0.0.gemspec")
    expect(Gem::Specification).to receive(:stubs).once.and_return([default_specification])

    expect(cache.cache_paths).not_to include(temporary_directory.join("installed/gems/first-2.0.0").to_s)
    cache.cache_paths
  end

  it "audits supplied paths against installed gemspecs" do
    specification = Gem::Specification.new do |spec|
      spec.name = "first"
      spec.version = "2.0.0"
      spec.summary = "first"
      spec.authors = ["test"]
      spec.files = []
    end
    write("installed/specifications/first-2.0.0.gemspec", specification.to_ruby)
    temporary_directory.join("installed/gems/first-2.0.0").mkpath
    paths = cache.cache_paths.first(3)

    expect { cache.audit_cache_paths(paths) }.not_to raise_error
  end

  it "rejects a partition whose installed gemspec is missing" do
    paths = cache.cache_paths.first(3)

    expect { cache.audit_cache_paths(paths) }.to raise_error(
      "Installed gemspec not found: #{temporary_directory}/installed/specifications/first-2.0.0.gemspec",
    )
  end

  it "rejects a partition whose executable directory is missing" do
    executable_path = temporary_directory.join("installed/bin").to_s

    expect { cache.audit_cache_paths([executable_path]) }.to raise_error(
      "Installed executable directory not found: #{executable_path}",
    )
  end

  it "installs appraisal Gemfiles without reinstalling base" do
    commands = []
    allow(cache).to receive(:system) do |environment, command, *arguments|
      commands << [environment.fetch("BUNDLE_GEMFILE"), command, *arguments]
      true
    end

    cache.install_appraisals

    expect(commands.map(&:first)).to contain_exactly(
      temporary_directory.join("first.gemfile").to_s,
      temporary_directory.join("second.gemfile").to_s,
    )
  end

  it "validates with supplied paths instead of recalculating them" do
    paths = []
    write("base-bundle/base.txt", "base")
    expect(cache).to receive(:audit_cache_paths).with(paths)
    expect(cache).not_to receive(:cache_paths)
    allow(cache).to receive(:system).and_return(true)

    cache.validate_partition(
      paths: paths,
      base_bundle_path: temporary_directory.join("base-bundle"),
      validation_path: temporary_directory.join("validation"),
    )
  end

  it "checks reconstructed bundles as system gem homes" do
    bundle_path = temporary_directory.join("validation")
    expect(cache).to receive(:system).with(
      {
        "BUNDLE_GEMFILE" => temporary_directory.join("first.gemfile").to_s,
        "BUNDLE_PATH" => nil,
        "GEM_HOME" => bundle_path.to_s,
        "GEM_PATH" => [bundle_path, Gem.default_dir].join(File::PATH_SEPARATOR),
      },
      "bundle",
      "check",
    ).and_return(true)

    cache.send(:run_bundle, temporary_directory.join("first.gemfile"), "check", bundle_path: bundle_path)
  end

  it "requires group scope when computing cache paths" do
    ungrouped = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: [],
    )

    expect { ungrouped.cache_paths }.to raise_error(ArgumentError, "cache paths require a group")
  end
end
