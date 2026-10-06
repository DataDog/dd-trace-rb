# Runs without Bundler.
require "bundler"
require "digest"
require "json"
require_relative "github_matrix"

class InstalledBundleCache
  CACHE_KEY_PREFIX = "bundle-installed-matrix-v3"
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

  attr_reader :root, :base_gemfile, :applicable_gemfiles

  def initialize(base_gemfile: AppraisalConversion.parent_gemfile)
    @root = Dir.pwd
    @base_gemfile = absolute_path(base_gemfile)
    @applicable_gemfiles = GithubMatrix.new.gemfiles.map { |path| absolute_path(path) }.sort
  end

  def gemfiles
    ([base_gemfile] + applicable_gemfiles).uniq
  end

  def appraisal_gemfiles
    applicable_gemfiles.reject { |gemfile| gemfile == base_gemfile }
  end

  def identity(image_identity:, base_cache_key:)
    {
      "base_cache_key" => base_cache_key,
      "bundler_settings" => bundler_settings,
      "content" => content,
      "image_identity" => image_identity,
      "native_build_overrides" => native_build_overrides,
    }
  end

  def content
    gemfiles.map do |gemfile|
      lockfile = lockfile_for(gemfile)
      [
        relative_path(gemfile),
        Digest::SHA256.file(gemfile).hexdigest,
        relative_path(lockfile),
        Digest::SHA256.file(lockfile).hexdigest,
      ]
    end
  end

  def identity_digest(image_identity:, base_cache_key:)
    digest_json(identity(image_identity: image_identity, base_cache_key: base_cache_key))
  end

  def cache_key(image_identity:, base_cache_key:)
    "#{CACHE_KEY_PREFIX}-#{identity_digest(image_identity: image_identity, base_cache_key: base_cache_key)}"
  end

  def install_appraisals
    appraisal_gemfiles.each { |gemfile| run_bundle(gemfile, "install") }
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
    path = "#{gemfile}.lock"
    raise "Lockfile not found: #{relative_path(path)}" unless File.file?(path)

    path
  end

  def absolute_path(path)
    File.expand_path(path, root)
  end

  def relative_path(path)
    expanded_path = File.expand_path(path)
    root_prefix = "#{root}/"
    expanded_path.start_with?(root_prefix) ? expanded_path[root_prefix.length..-1] : expanded_path
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"

  options = {}
  parser = OptionParser.new do |opts|
    opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
    opts.on("--base-cache-key VALUE") { |value| options[:base_cache_key] = value }
    opts.on("--image-identity VALUE") { |value| options[:image_identity] = value }
  end

  command = ARGV.shift
  parser.parse!(ARGV)
  raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]

  cache = InstalledBundleCache.new(base_gemfile: options[:base_gemfile])

  case command
  when "key"
    raise OptionParser::MissingArgument, "--base-cache-key" unless options[:base_cache_key]
    raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

    puts cache.cache_key(
      image_identity: options[:image_identity],
      base_cache_key: options[:base_cache_key],
    )
  when "install-appraisals"
    cache.install_appraisals
  when "check"
    cache.check
  else
    warn parser
    exit 1
  end
end
