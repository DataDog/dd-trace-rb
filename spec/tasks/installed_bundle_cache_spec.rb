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

  it "changes only the content digest for an experimental key variant" do
    original_environment = cache.environment_digest(image_identity: "image-a")
    original_content = cache.content_digest
    variant_content = cache.content_digest(experiment_variant: "generation-b")

    expect(variant_content).not_to eq(original_content)
    expect(cache.environment_digest(image_identity: "image-a")).to eq(original_environment)
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

  it "includes deterministic batch-group membership in grouped content" do
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-full",
      group: {
        "name" => "standard-0",
        "tasks" => [
          {"task" => "redis", "group" => "redis", "gemfile" => "first.gemfile"},
          {"gemfile" => "base.gemfile", "group" => "fallback", "task" => "fallback"},
        ],
      },
    )

    expect(grouped_cache.content.fetch("group")).to eq(
      "name" => "standard-0",
      "tasks" => [
        {"gemfile" => "base.gemfile", "group" => "fallback", "task" => "fallback"},
        {"gemfile" => "first.gemfile", "group" => "redis", "task" => "redis"},
      ],
    )
  end

  it "invalidates grouped content when task membership changes" do
    first_group = {"name" => "standard-0", "tasks" => [{"task" => "redis", "group" => "redis", "gemfile" => "first.gemfile"}]}
    second_group = {"name" => "standard-0", "tasks" => [{"task" => "http", "group" => "redis", "gemfile" => "first.gemfile"}]}
    first_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-full",
      group: first_group,
    )
    second_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-full",
      group: second_group,
    )

    expect(first_cache.content_digest).not_to eq(second_cache.content_digest)
  end

  it "requires a base cache key for group-delta" do
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      group: {"name" => "standard-0", "tasks" => []},
    )

    expect { grouped_cache.content_digest }.to raise_error(
      ArgumentError,
      "base_cache_key is required for group-delta strategy",
    )
  end

  it "builds a full group from the preserved base" do
    write("base-bundle/gems/base.rb", "base\n")
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-full",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )
    allow(grouped_cache).to receive(:system) do |_environment, _command, *arguments|
      write("installed/gems/group.rb", "group\n") if arguments.first == "install"
      true
    end

    grouped_cache.prepare_group(
      base_bundle_path: temporary_directory.join("base-bundle"),
      cache_path: temporary_directory.join("group-cache"),
      base_snapshot_path: temporary_directory.join("unused-snapshot"),
      restore_status: "miss",
      write_enabled: true,
    )

    expect(temporary_directory.join("group-cache/gems/base.rb").read).to eq("base\n")
    expect(temporary_directory.join("group-cache/gems/group.rb").read).to eq("group\n")
  end

  it "maps group-only specs to direct installed cache paths" do
    write("base.gemfile.lock", lockfile("base (1.0.0)", "shared (1.0.0)"))
    write("first.gemfile.lock", lockfile("base (1.0.0)", "group (2.0.0)", "shared (1.0.0)"))
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )

    expect(grouped_cache.cache_paths).to contain_exactly(
      temporary_directory.join("installed/gems/group-2.0.0").to_s,
      temporary_directory.join("installed/specifications/group-2.0.0.gemspec").to_s,
      temporary_directory.join(
        "installed/extensions/#{Gem::Platform.local}/#{Gem.extension_api_version}/group-2.0.0"
      ).to_s,
    )
  end

  it "omits default gems supplied by the Ruby installation" do
    write("base.gemfile.lock", lockfile("base (1.0.0)"))
    write("first.gemfile.lock", lockfile("base (1.0.0)", "group (2.0.0)"))
    default_specification = Gem::Specification.new do |spec|
      spec.name = "group"
      spec.version = "2.0.0"
    end
    allow(Gem::Specification).to receive(:default_stubs).and_return([default_specification])
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )

    expect(grouped_cache.cache_paths).to be_empty
  end

  it "audits paths against the installed gemspec" do
    write("base.gemfile.lock", lockfile("base (1.0.0)"))
    write("first.gemfile.lock", lockfile("base (1.0.0)", "group (2.0.0)"))
    specification = Gem::Specification.new do |spec|
      spec.name = "group"
      spec.version = "2.0.0"
      spec.summary = "group"
      spec.authors = ["test"]
      spec.files = []
    end
    write("installed/specifications/group-2.0.0.gemspec", specification.to_ruby)
    temporary_directory.join("installed/gems/group-2.0.0").mkpath
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )

    expect { grouped_cache.audit_cache_paths }.not_to raise_error
  end

  it "rejects a partition whose installed gemspec is missing" do
    write("base.gemfile.lock", lockfile("base (1.0.0)"))
    write("first.gemfile.lock", lockfile("base (1.0.0)", "group (2.0.0)"))
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )

    expect { grouped_cache.audit_cache_paths }.to raise_error(
      "Installed gemspec not found: #{temporary_directory}/installed/specifications/group-2.0.0.gemspec",
    )
  end

  it "includes direct group paths in group-delta manifests" do
    write("base.gemfile.lock", lockfile("base (1.0.0)"))
    write("first.gemfile.lock", lockfile("base (1.0.0)", "group (2.0.0)"))
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )

    manifest = grouped_cache.to_h(
      cache_schema: "installed-test-v1-group-delta",
      image_identity: "image-a",
      base_cache_key: "base-key",
    )

    expect(manifest.fetch(:cache_paths)).to eq(grouped_cache.cache_paths)
  end

  it "builds a group delta without unchanged base files" do
    write("base-bundle/gems/base.rb", "base\n")
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )
    write("installed/gems/base.rb", "base\n")
    grouped_cache.write_snapshot(temporary_directory.join("base-snapshot.json"))
    allow(grouped_cache).to receive(:system) do |_environment, _command, *arguments|
      write("installed/gems/group.rb", "group\n") if arguments.first == "install"
      true
    end

    grouped_cache.prepare_group(
      base_bundle_path: temporary_directory.join("base-bundle"),
      cache_path: temporary_directory.join("group-cache"),
      base_snapshot_path: temporary_directory.join("base-snapshot.json"),
      restore_status: "miss",
      write_enabled: true,
    )

    expect(temporary_directory.join("group-cache/gems/base.rb")).not_to exist
    expect(temporary_directory.join("group-cache/gems/group.rb").read).to eq("group\n")
  end

  it "repairs a partially restored group delta over the preserved base" do
    write("base-bundle/gems/base.rb", "base\n")
    write("group-cache/gems/group.rb", "group\n")
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-delta",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )
    allow(grouped_cache).to receive(:system).and_return(true)

    grouped_cache.prepare_group(
      base_bundle_path: temporary_directory.join("base-bundle"),
      cache_path: temporary_directory.join("group-cache"),
      base_snapshot_path: temporary_directory.join("unused-snapshot"),
      restore_status: "partial",
      write_enabled: false,
    )

    expect(temporary_directory.join("installed/gems/base.rb").read).to eq("base\n")
    expect(temporary_directory.join("installed/gems/group.rb").read).to eq("group\n")
  end

  it "rejects an unknown group restore status" do
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-full",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )

    expect do
      grouped_cache.prepare_group(
        base_bundle_path: temporary_directory.join("base-bundle"),
        cache_path: temporary_directory.join("group-cache"),
        base_snapshot_path: temporary_directory.join("unused-snapshot"),
        restore_status: "unknown",
        write_enabled: false,
      )
    end.to raise_error(ArgumentError, "Unknown restore status: unknown")
  end

  it "does not repair a read-only group miss" do
    grouped_cache = described_class.new(
      root: temporary_directory,
      base_gemfile: "base.gemfile",
      applicable_gemfiles: ["first.gemfile"],
      strategy: "group-full",
      installed_path: temporary_directory.join("installed"),
      group: {"name" => "standard-0", "tasks" => []},
    )
    expect(grouped_cache).not_to receive(:system)

    grouped_cache.prepare_group(
      base_bundle_path: temporary_directory.join("base-bundle"),
      cache_path: temporary_directory.join("group-cache"),
      base_snapshot_path: temporary_directory.join("unused-snapshot"),
      restore_status: "miss",
      write_enabled: false,
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

    cache.send(
      :run_bundle,
      temporary_directory.join("first.gemfile"),
      "check",
      bundle_path: bundle_path,
    )
  end

  it "rejects missing lockfiles" do
    temporary_directory.join("first.gemfile.lock").delete

    expect { cache.lockfiles }.to raise_error("Lockfile not found: first.gemfile.lock")
  end
end
