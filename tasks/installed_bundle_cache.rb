require "bundler"
require "digest"
require "json"
require "pathname"
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

  attr_reader :root, :base_gemfile, :applicable_gemfiles, :installed_path

  def initialize(
    root: Pathname.pwd,
    base_gemfile: AppraisalConversion.parent_gemfile,
    matrix: GithubMatrix.new,
    installed_path: "/usr/local/bundle"
  )
    @root = Pathname(root).expand_path
    @base_gemfile = absolute_path(base_gemfile)
    @applicable_gemfiles = matrix.gemfiles.map { |path| absolute_path(path) }.sort
    @installed_path = Pathname(installed_path).expand_path
  end

  def gemfiles
    ([base_gemfile] + applicable_gemfiles).uniq
  end

  def environment(image_identity:)
    {
      "bundler_settings" => bundler_settings,
      "image_identity" => image_identity,
      "installed_path" => installed_path.to_s,
      "native_build_overrides" => native_build_overrides,
    }
  end

  def content
    gemfiles.flat_map { |gemfile| [gemfile, lockfile_for(gemfile)] }.sort.map do |path|
      {
        "path" => relative_path(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end
  end

  def environment_digest(image_identity:)
    digest_json(environment(image_identity: image_identity))
  end

  def content_digest
    digest_json(content)
  end

  def cache_key(cache_schema:, image_identity:)
    [cache_schema, environment_digest(image_identity: image_identity), content_digest].join("-")
  end

  def to_h(cache_schema:, image_identity:)
    {
      cache_key: cache_key(cache_schema: cache_schema, image_identity: image_identity),
      environment: environment(image_identity: image_identity),
      content: content,
      environment_digest: environment_digest(image_identity: image_identity),
      content_digest: content_digest,
      base_gemfile: relative_path(base_gemfile),
      applicable_gemfiles: applicable_gemfiles.map { |path| relative_path(path) },
    }
  end

  def install(jobs: 8)
    gemfiles.each { |gemfile| run_bundle(gemfile, "install", "--jobs", jobs.to_s) }
  end

  def check
    gemfiles.each { |gemfile| run_bundle(gemfile, "check") }
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
