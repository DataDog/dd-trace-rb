require "bundler"
require "digest"
require "json"
require "pathname"
require "rbconfig"
require_relative "github_matrix"

class InstalledBundleCache
  BUILD_ENVIRONMENT_KEYS = %w[
    ARCHFLAGS
    BUNDLE_CLEAN
    BUNDLE_FORCE_RUBY_PLATFORM
    BUNDLE_ONLY
    BUNDLE_WITH
    BUNDLE_WITHOUT
    CFLAGS
    CPPFLAGS
    CXXFLAGS
    LDFLAGS
    MAKEFLAGS
  ].freeze

  attr_reader :root, :base_gemfile, :appraisal_gemfiles

  def initialize(root: Pathname.pwd, base_gemfile: AppraisalConversion.parent_gemfile, matrix: nil, appraisal_gemfiles: nil)
    raise ArgumentError, "Provide matrix or appraisal_gemfiles, not both" if matrix && appraisal_gemfiles

    @root = Pathname(root).expand_path
    @base_gemfile = absolute_path(base_gemfile)
    selected_gemfiles = appraisal_gemfiles || (matrix || GithubMatrix.new).appraisal_gemfiles
    @appraisal_gemfiles = selected_gemfiles.map { |path| absolute_path(path) }.sort
  end

  def gemfiles
    ([base_gemfile] + appraisal_gemfiles).uniq
  end

  def lockfiles
    gemfiles.map { |gemfile| lockfile_for(gemfile) }.sort
  end

  def lockfile_digest
    digest_paths(lockfiles)
  end

  def environment(image_identity:)
    {
      image_identity: image_identity,
      ruby_description: RUBY_DESCRIPTION,
      extension_api_version: Gem.extension_api_version,
      platform: Gem::Platform.local.to_s,
      architecture: RbConfig::CONFIG.fetch("host_cpu"),
      bundler_version: Bundler::VERSION,
      build_configuration_digest: build_configuration_digest,
    }
  end

  def cache_key(cache_schema:, image_identity:)
    environment_digest = Digest::SHA256.hexdigest(JSON.generate(environment(image_identity: image_identity)))
    "#{cache_schema}-#{AppraisalConversion.runtime_identifier}-#{environment_digest}-#{lockfile_digest}"
  end

  def to_h(cache_schema:, image_identity:)
    {
      cache_schema: cache_schema,
      cache_key: cache_key(cache_schema: cache_schema, image_identity: image_identity),
      environment: environment(image_identity: image_identity),
      base_gemfile: relative_path(base_gemfile),
      appraisal_gemfiles: appraisal_gemfiles.map { |path| relative_path(path) },
      lockfiles: lockfiles.map { |path| relative_path(path) },
      lockfile_digest: lockfile_digest,
    }
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

  private

  def build_configuration_digest
    settings = Bundler.settings.all.grep(/\A(?:build\.|clean|deployment|force_ruby_platform|frozen|only|path|with|without)\z/).sort.map do |key|
      [key, Bundler.settings[key]]
    end
    environment = ENV.select do |key, _value|
      BUILD_ENVIRONMENT_KEYS.include?(key) || key.start_with?("BUNDLE_BUILD__")
    end.sort

    Digest::SHA256.hexdigest(JSON.generate(settings: settings, environment: environment))
  end

  def digest_paths(paths)
    digest = Digest::SHA256.new

    paths.each do |path|
      digest << relative_path(path) << "\0" << File.binread(path) << "\0"
    end

    digest.hexdigest
  end

  def run_bundle(gemfile, *arguments)
    relative_gemfile = relative_path(gemfile)
    puts "BUNDLE_GEMFILE=#{relative_gemfile} bundle #{arguments.join(" ")}"
    success = system({"BUNDLE_GEMFILE" => gemfile.to_s}, "bundle", *arguments)
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
