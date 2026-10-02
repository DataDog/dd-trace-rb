require "bundler"
require "digest"
require "fileutils"
require "json"
require "pathname"
require "set"
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
    force_ruby_platform
    only
    with
    without
  ].freeze

  attr_reader :root, :base_gemfile, :applicable_gemfiles, :installed_path, :group

  def initialize(
    root: Pathname.pwd,
    base_gemfile: AppraisalConversion.parent_gemfile,
    matrix: nil,
    applicable_gemfiles: nil,
    installed_path: "/usr/local/bundle",
    group: nil
  )
    raise ArgumentError, "Provide matrix or applicable_gemfiles, not both" if matrix && applicable_gemfiles

    @root = Pathname(root).expand_path
    @base_gemfile = absolute_path(base_gemfile)
    selected_gemfiles = applicable_gemfiles || (matrix || GithubMatrix.new).gemfiles
    @applicable_gemfiles = selected_gemfiles.map { |path| absolute_path(path) }.uniq.sort
    @installed_path = Pathname(installed_path).expand_path
    @group = group
  end

  def gemfiles
    ([base_gemfile] + applicable_gemfiles).uniq
  end

  def environment(image_identity:)
    {
      "bundler_settings" => bundler_settings,
      "image_identity" => image_identity,
      "native_build_overrides" => native_build_overrides,
    }
  end

  def content(base_cache_key:)
    {
      "base_cache_key" => required_base_cache_key(base_cache_key),
      "members" => appraisal_gemfiles.flat_map do |gemfile|
        [gemfile, lockfile_for(gemfile)]
      end.sort.map do |path|
        {
          "path" => relative_path(path),
          "sha256" => Digest::SHA256.file(path).hexdigest,
        }
      end,
    }
  end

  def environment_digest(image_identity:)
    digest_json(environment(image_identity: image_identity))
  end

  def content_digest(base_cache_key:)
    digest_json(content(base_cache_key: base_cache_key))
  end

  def cache_key(cache_schema:, image_identity:, base_cache_key:)
    [
      cache_schema,
      environment_digest(image_identity: image_identity),
      content_digest(base_cache_key: base_cache_key),
    ].join("-")
  end

  def to_h(cache_schema:, image_identity:, base_cache_key:)
    {
      cache_key: cache_key(
        cache_schema: cache_schema,
        image_identity: image_identity,
        base_cache_key: base_cache_key,
      ),
      environment: environment(image_identity: image_identity),
      content: content(base_cache_key: base_cache_key),
      environment_digest: environment_digest(image_identity: image_identity),
      content_digest: content_digest(base_cache_key: base_cache_key),
      base_gemfile: relative_path(base_gemfile),
      applicable_gemfiles: applicable_gemfiles.map { |path| relative_path(path) },
      group: group,
      cache_paths: cache_paths,
    }
  end

  def cache_paths
    raise ArgumentError, "cache paths require a group" unless group

    base_identities = base_specifications.each_with_object(Set.new) do |spec, identities|
      identities << specification_package_identity(spec)
    end
    specifications = selected_specifications.reject do |spec|
      base_identities.include?(specification_package_identity(spec)) || default_specification?(spec)
    end.sort_by { |spec| specification_identity(spec) }
    return [] if specifications.empty?

    specifications.flat_map do |spec|
      full_name = spec.full_name
      [
        installed_path.join("gems", full_name),
        installed_path.join("specifications", "#{full_name}.gemspec"),
        installed_path.join("extensions", Gem::Platform.local.to_s, Gem.extension_api_version, full_name),
      ].map(&:to_s)
    end + [installed_path.join("bin").to_s]
  end

  def prepare_partitioned_groups(groups:, base_bundle_path:, validation_path:, jobs: 8)
    reset_installed_from(base_bundle_path)
    union_gemfiles = groups.values.flat_map do |value|
      value.fetch("tasks").map { |task| task.fetch("gemfile") }
    end.uniq
    InstalledBundleCache.new(
      root: root,
      base_gemfile: base_gemfile,
      applicable_gemfiles: union_gemfiles,
      installed_path: installed_path,
    ).install_appraisals(jobs: jobs)

    groups.sort.each do |_name, value|
      group_cache = InstalledBundleCache.new(
        root: root,
        base_gemfile: base_gemfile,
        applicable_gemfiles: value.fetch("tasks").map { |task| task.fetch("gemfile") }.uniq,
        installed_path: installed_path,
        group: value.fetch("name"),
      )
      paths = group_cache.cache_paths
      group_cache.validate_partition(
        paths: paths,
        base_bundle_path: base_bundle_path,
        validation_path: validation_path,
      )
    end
  end

  def install_appraisals(jobs: 8)
    appraisal_gemfiles.each do |gemfile|
      run_bundle(gemfile, "install", "--jobs", jobs.to_s)
    end
  end

  def validate_partition(paths:, base_bundle_path:, validation_path:)
    audit_cache_paths(paths)
    validation_path = Pathname(validation_path).expand_path
    reset_path_from(validation_path, base_bundle_path)
    copy_relative_paths(installed_path, validation_path, paths)
    gemfiles.each do |gemfile|
      run_bundle(gemfile, "check", bundle_path: validation_path)
    end
  ensure
    FileUtils.rm_rf(validation_path) if validation_path
  end

  def audit_cache_paths(paths)
    executable_path = installed_path.join("bin").to_s
    gem_paths = paths.reject { |path| Pathname(path).expand_path.to_s == executable_path }
    if paths.include?(executable_path) && !File.directory?(executable_path)
      raise "Installed executable directory not found: #{executable_path}"
    end

    gem_paths.each_slice(3) do |gem_path, gemspec_path, extension_path|
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

  private

  def appraisal_gemfiles
    applicable_gemfiles.reject { |gemfile| gemfile == base_gemfile }
  end

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
      selected[key] = value if BUILD_ENVIRONMENT_KEYS.include?(key)
    end
  end

  def required_base_cache_key(base_cache_key)
    raise ArgumentError, "base_cache_key is required" if base_cache_key.to_s.empty?

    base_cache_key
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
      selected.concat(Bundler::MatchPlatform.select_best_platform_match(variants, Gem::Platform.local))
    end
  end

  def specification_identity(spec)
    [spec.name, spec.version.to_s, spec.platform.to_s, source_identity(spec.source)]
  end

  def specification_package_identity(spec)
    [spec.name, spec.version.to_s, source_identity(spec.source)]
  end

  def default_specification?(spec)
    default_specification_identities.include?([spec.name, spec.version.to_s, spec.platform.to_s])
  end

  def default_specification_identities
    @default_specification_identities ||= begin
      default_directory = Pathname(Gem.default_dir).expand_path
      Gem::Specification.stubs.each_with_object(Set.new) do |spec, identities|
        installed_in_default_directory = Pathname(spec.loaded_from).expand_path.ascend.any? do |path|
          path == default_directory
        end
        identities << [spec.name, spec.version.to_s, spec.platform.to_s] if installed_in_default_directory
      end
    end
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

  def run_bundle(gemfile, *arguments, bundle_path: nil)
    relative_gemfile = relative_path(gemfile)
    puts "BUNDLE_GEMFILE=#{relative_gemfile} bundle #{arguments.join(" ")}"
    environment = {"BUNDLE_GEMFILE" => gemfile.to_s}
    if bundle_path
      environment.merge!(
        "BUNDLE_PATH" => nil,
        "GEM_HOME" => bundle_path.to_s,
        "GEM_PATH" => [bundle_path, Gem.default_dir].join(File::PATH_SEPARATOR),
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
