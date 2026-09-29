require "bundler"
require "digest"
require "fileutils"
require "json"
require "pathname"
require "rbconfig"
require_relative "github_matrix"

class InstalledBundleCache
  BUILD_ENVIRONMENT_KEYS = %w[
    ARCHFLAGS
    CFLAGS
    CPPFLAGS
    CXXFLAGS
    LDFLAGS
    MAKEFLAGS
  ].freeze
  BUNDLER_SETTING_KEYS = %w[
    cache_all
    cache_path
    force_ruby_platform
    frozen
    no_prune
    only
    with
    without
  ].freeze
  STRATEGIES = %w[full all-delta group-full group-delta].freeze
  RESTORE_STATUSES = %w[exact partial miss].freeze

  attr_reader :root, :base_gemfile, :applicable_gemfiles, :strategy, :installed_path, :group

  def initialize(
    root: Pathname.pwd,
    base_gemfile: AppraisalConversion.parent_gemfile,
    matrix: nil,
    applicable_gemfiles: nil,
    strategy: "full",
    installed_path: "/usr/local/bundle",
    group: nil
  )
    raise ArgumentError, "Provide matrix or applicable_gemfiles, not both" if matrix && applicable_gemfiles
    raise ArgumentError, "Unknown strategy: #{strategy}" unless STRATEGIES.include?(strategy)

    @root = Pathname(root).expand_path
    @base_gemfile = absolute_path(base_gemfile)
    selected_gemfiles = applicable_gemfiles || (matrix || GithubMatrix.new).gemfiles
    @applicable_gemfiles = selected_gemfiles.map { |path| absolute_path(path) }.sort
    @strategy = strategy
    @installed_path = Pathname(installed_path).expand_path
    @group = normalize_group(group)
  end

  def gemfiles
    ([base_gemfile] + applicable_gemfiles).uniq
  end

  def lockfiles
    gemfiles.map { |gemfile| lockfile_for(gemfile) }.sort
  end

  def lockfile_digest
    digest_paths(lockfiles)
  end

  def environment(image_identity:)
    {
      "bundler_settings" => bundler_settings,
      "image_identity" => image_identity,
      "installed_path" => installed_path.to_s,
      "native_build_overrides" => native_build_overrides,
      "rubygems_version" => Gem::VERSION,
    }
  end

  def content(base_cache_key: nil, experiment_variant: nil)
    members = content_gemfiles.flat_map do |gemfile|
      [gemfile, lockfile_for(gemfile)]
    end.sort.map do |path|
      {
        "path" => relative_path(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end

    content = {"members" => members}
    content["group"] = group if group
    content["base_cache_key"] = required_base_cache_key(base_cache_key) if delta_strategy?
    content["experiment_variant"] = experiment_variant unless experiment_variant.to_s.empty?
    content
  end

  def environment_digest(image_identity:)
    digest_json(environment(image_identity: image_identity))
  end

  def content_digest(base_cache_key: nil, experiment_variant: nil)
    digest_json(content(base_cache_key: base_cache_key, experiment_variant: experiment_variant))
  end

  def cache_key(cache_schema:, image_identity:, base_cache_key: nil, experiment_variant: nil)
    [
      cache_schema,
      environment_digest(image_identity: image_identity),
      content_digest(base_cache_key: base_cache_key, experiment_variant: experiment_variant),
    ].join("-")
  end

  def restore_prefix(cache_schema:, image_identity:)
    "#{cache_schema}-#{environment_digest(image_identity: image_identity)}-"
  end

  def to_h(cache_schema:, image_identity:, base_cache_key: nil, experiment_variant: nil)
    manifest = {
      cache_schema: cache_schema,
      strategy: strategy,
      cache_key: cache_key(
        cache_schema: cache_schema,
        image_identity: image_identity,
        base_cache_key: base_cache_key,
        experiment_variant: experiment_variant,
      ),
      restore_prefix: restore_prefix(cache_schema: cache_schema, image_identity: image_identity),
      environment: environment(image_identity: image_identity),
      content: content(base_cache_key: base_cache_key, experiment_variant: experiment_variant),
      environment_digest: environment_digest(image_identity: image_identity),
      content_digest: content_digest(base_cache_key: base_cache_key, experiment_variant: experiment_variant),
      base_gemfile: relative_path(base_gemfile),
      applicable_gemfiles: applicable_gemfiles.map { |path| relative_path(path) },
      group: group,
    }
    manifest[:cache_paths] = cache_paths if strategy == "group-delta"
    manifest
  end

  def install(jobs: 8)
    gemfiles.each do |gemfile|
      run_bundle(gemfile, "install", "--jobs", jobs.to_s)
    end
  end

  def check
    gemfiles.each do |gemfile|
      run_bundle(gemfile, "check")
    end
  end

  def snapshot
    installed_entries.each_with_object({}) do |path, entries|
      relative = path.relative_path_from(installed_path).to_s
      entries[relative] = entry_identity(path)
    end
  end

  def write_snapshot(path)
    Pathname(path).write(JSON.pretty_generate(snapshot))
  end

  def extract_delta(base_snapshot_path:, destination:)
    base_snapshot = JSON.parse(Pathname(base_snapshot_path).read)
    destination = Pathname(destination).expand_path
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)

    snapshot.each do |relative, identity|
      next if base_snapshot[relative] == identity

      source = installed_path.join(relative)
      target = destination.join(relative)
      FileUtils.mkdir_p(target.dirname)
      FileUtils.copy_entry(source, target, true, false, true)
    end
  end

  def prepare_group(base_bundle_path:, cache_path:, base_snapshot_path:, restore_status:, write_enabled:, jobs: 8)
    raise ArgumentError, "Unknown restore status: #{restore_status}" unless RESTORE_STATUSES.include?(restore_status)
    return if restore_status == "exact"
    return if restore_status == "miss" && !write_enabled

    cache_path = Pathname(cache_path).expand_path
    source = (restore_status == "partial" && strategy == "group-full") ? cache_path : base_bundle_path
    reset_installed_from(source)
    copy_contents(cache_path, installed_path) if restore_status == "partial" && strategy == "group-delta"
    install(jobs: jobs)
    check
    return unless write_enabled

    if strategy == "group-delta"
      extract_delta(base_snapshot_path: base_snapshot_path, destination: cache_path)
    else
      reset_path_from(cache_path, installed_path)
    end
  end

  def cache_paths
    raise ArgumentError, "cache paths require a group" unless group

    base_identities = base_specifications.map { |spec| specification_identity(spec) }
    selected_specifications.reject do |spec|
      base_identities.include?(specification_identity(spec))
    end.sort_by { |spec| specification_identity(spec) }.flat_map do |spec|
      full_name = spec.full_name
      [
        installed_path.join("gems", full_name),
        installed_path.join("specifications", "#{full_name}.gemspec"),
        installed_path.join("extensions", Gem::Platform.local.to_s, Gem.extension_api_version, full_name),
      ].map(&:to_s)
    end
  end

  def prepare_partitioned_groups(groups:, base_bundle_path:, validation_path:, jobs: 8)
    reset_installed_from(base_bundle_path)
    InstalledBundleCache.new(
      root: root,
      base_gemfile: base_gemfile,
      applicable_gemfiles: groups.values.flat_map { |value| value.fetch("tasks").map { |task| task.fetch("gemfile") } }.uniq,
      strategy: strategy,
      installed_path: installed_path,
    ).install(jobs: jobs)

    groups.sort.each do |_name, value|
      group_cache = InstalledBundleCache.new(
        root: root,
        base_gemfile: base_gemfile,
        applicable_gemfiles: value.fetch("tasks").map { |task| task.fetch("gemfile") }.uniq,
        strategy: strategy,
        installed_path: installed_path,
        group: value,
      )
      group_cache.validate_partition(base_bundle_path: base_bundle_path, validation_path: validation_path)
    end
  end

  def validate_partition(base_bundle_path:, validation_path:)
    audit_cache_paths
    validation_path = Pathname(validation_path).expand_path
    reset_path_from(validation_path, base_bundle_path)
    copy_relative_paths(installed_path, validation_path, cache_paths)
    gemfiles.each do |gemfile|
      run_bundle(gemfile, "check", bundle_path: validation_path)
    end
  ensure
    FileUtils.rm_rf(validation_path) if validation_path
  end

  def audit_cache_paths
    cache_paths.each_slice(3) do |gem_path, gemspec_path, extension_path|
      raise "Installed gemspec not found: #{gemspec_path}" unless File.file?(gemspec_path)

      spec = Gem::Specification.load(gemspec_path)
      raise "Invalid installed gemspec: #{gemspec_path}" unless spec

      expected = [spec.full_gem_path, spec.loaded_from, spec.extension_dir].map { |path| Pathname(path).expand_path.to_s }
      actual = [gem_path, gemspec_path, extension_path].map { |path| Pathname(path).expand_path.to_s }
      raise "Installed paths do not match #{spec.full_name}" unless actual == expected
      raise "Installed gem directory not found: #{gem_path}" unless File.directory?(gem_path)
      if spec.extensions.any? && !File.directory?(extension_path)
        raise "Installed extension directory not found: #{extension_path}"
      end
    end
  end

  def cache_statistics
    files = cache_paths.flat_map do |path|
      path = Pathname(path)
      path.directory? ? path.glob("**/*", File::FNM_DOTMATCH).reject(&:directory?) : [path]
    end.select(&:file?)

    {
      "file_count" => files.size,
      "byte_count" => files.sum(&:size),
    }
  end

  private

  def canonical_json(value)
    case value
    when Hash
      "{" + value.keys.map(&:to_s).sort.map do |key|
        original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        "#{JSON.generate(key)}:#{canonical_json(value.fetch(original_key))}"
      end.join(",") + "}"
    when Array
      "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
    else
      JSON.generate(value)
    end
  end

  def digest_json(value)
    Digest::SHA256.hexdigest(canonical_json(value))
  end

  def bundler_settings
    Bundler.settings.all.sort.each_with_object({}) do |key, selected|
      next unless BUNDLER_SETTING_KEYS.include?(key) || key.start_with?("build.")

      selected[key] = Bundler.settings[key]
    end
  end

  def native_build_overrides
    ENV.sort.each_with_object({}) do |(key, value), selected|
      if BUILD_ENVIRONMENT_KEYS.include?(key) || key.start_with?("BUNDLE_BUILD__")
        selected[key] = value
      end
    end
  end

  def content_gemfiles
    delta_strategy? ? gemfiles.reject { |gemfile| gemfile == base_gemfile } : gemfiles
  end

  def delta_strategy?
    %w[all-delta group-delta].include?(strategy)
  end

  def required_base_cache_key(base_cache_key)
    raise ArgumentError, "base_cache_key is required for #{strategy} strategy" if base_cache_key.to_s.empty?

    base_cache_key
  end

  def normalize_group(value)
    return unless value

    {
      "name" => value.fetch("name"),
      "tasks" => value.fetch("tasks").map do |task|
        task.transform_keys(&:to_s).sort.to_h
      end.sort_by { |task| [task.fetch("task"), task.fetch("group"), task.fetch("gemfile")] },
    }
  end

  def selected_specifications
    specifications_for(gemfiles)
  end

  def base_specifications
    specifications_for([base_gemfile])
  end

  def specifications_for(selected_gemfiles)
    selected_gemfiles.flat_map do |gemfile|
      parser = Bundler::LockfileParser.new(File.read(lockfile_for(gemfile)))
      rubygems_specs(parser)
    end.uniq { |spec| specification_identity(spec) }
  end

  def rubygems_specs(parser)
    specs = parser.specs.select { |spec| spec.source.is_a?(Bundler::Source::Rubygems) }

    specs.group_by { |spec| [spec.name, spec.version.to_s, source_identity(spec.source)] }.each_with_object([]) do |(_identity, variants), selected|
      matching = variants.select { |spec| platform_match?(spec.platform) }
      native = matching.reject { |spec| spec.platform.to_s == "ruby" }
      selected.concat(native.empty? ? matching : native)
    end
  end

  def platform_match?(platform)
    platform.to_s == "ruby" || Gem::Platform.local === Gem::Platform.new(platform.to_s)
  end

  def specification_identity(spec)
    [spec.name, spec.version.to_s, spec.platform.to_s, source_identity(spec.source)]
  end

  def source_identity(source)
    [source.class.name, *source.remotes.map(&:to_s).sort]
  end

  def reset_installed_from(source)
    reset_path_from(installed_path, source)
  end

  def reset_path_from(destination, source)
    destination = Pathname(destination).expand_path
    source = Pathname(source).expand_path
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
    copy_contents(source, destination)
  end

  def copy_contents(source, destination)
    source = Pathname(source).expand_path
    destination = Pathname(destination).expand_path
    FileUtils.mkdir_p(destination)
    source.children.each do |entry|
      FileUtils.copy_entry(entry, destination.join(entry.basename), true, false, true)
    end
  end

  def copy_relative_paths(source_root, destination_root, paths)
    source_root = Pathname(source_root).expand_path
    destination_root = Pathname(destination_root).expand_path
    paths.each do |path|
      source = Pathname(path).expand_path
      next unless source.exist?

      relative = source.relative_path_from(source_root)
      target = destination_root.join(relative)
      FileUtils.mkdir_p(target.dirname)
      FileUtils.copy_entry(source, target, true, false, true)
    end
  end

  def installed_entries
    return [] unless installed_path.directory?

    installed_path.glob("**/*", File::FNM_DOTMATCH).reject do |path|
      [".", ".."].include?(path.basename.to_s) || path.directory?
    end.sort
  end

  def entry_identity(path)
    if path.symlink?
      "symlink:#{path.readlink}"
    else
      "file:#{Digest::SHA256.file(path).hexdigest}"
    end
  end

  def digest_paths(paths)
    digest = Digest::SHA256.new

    paths.each do |path|
      digest << relative_path(path) << "\0" << File.binread(path) << "\0"
    end

    digest.hexdigest
  end

  def run_bundle(gemfile, *arguments, bundle_path: nil)
    relative_gemfile = relative_path(gemfile)
    puts "BUNDLE_GEMFILE=#{relative_gemfile} bundle #{arguments.join(" ")}"
    environment = {"BUNDLE_GEMFILE" => gemfile.to_s}
    if bundle_path
      environment.merge!(
        "BUNDLE_PATH" => bundle_path.to_s,
        "GEM_HOME" => bundle_path.to_s,
        "GEM_PATH" => bundle_path.to_s,
      )
    end
    success = system(environment, "bundle", *arguments)
    raise "bundle #{arguments.first} failed for #{relative_gemfile}" unless success
  end

  def lockfile_for(gemfile)
    path = Pathname("#{gemfile}.lock")
    raise "Lockfile not found: #{relative_path(path)}" unless path.file?

    path
  end

  def absolute_path(path)
    path = Pathname(path)
    path.absolute? ? path : root.join(path)
  end

  def relative_path(path)
    Pathname(path).relative_path_from(root).to_s
  rescue ArgumentError
    Pathname(path).to_s
  end
end
