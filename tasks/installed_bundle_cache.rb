require "bundler"
require "digest"
require "json"

class InstalledBundleCache
  BASE_CACHE_KEY_PREFIX = "bundle-base-v1"
  CACHE_KEY_PREFIX = "bundle-installed-matrix-v3"
  CACHE_RECIPE_FILES = %w[
    .github/actions/bundle-cache/action.yml
    .github/actions/installed-bundle-cache/action.yml
    tasks/github.rake
    tasks/installed_bundle_cache.rb
  ].freeze
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

  def initialize(base_gemfile:, gemfiles: [])
    @root = Dir.pwd
    @base_gemfile = absolute_path(base_gemfile)
    @gemfiles = gemfiles.map { |path| absolute_path(path) }
  end

  def base_cache_key(image_identity:)
    identity = {
      "bundler_settings" => bundler_settings,
      "dependencies" => dependency_content(@base_gemfile),
      "image_identity" => image_identity,
      "native_build_overrides" => native_build_overrides,
      "recipe" => recipe_fingerprint,
    }
    "#{BASE_CACHE_KEY_PREFIX}-#{digest(identity)}"
  end

  def cache_key(base_cache_key:)
    identity = {
      "base_cache_key" => base_cache_key,
      "dependencies" => @gemfiles.map { |gemfile| dependency_content(gemfile) }.uniq.sort,
    }
    "#{CACHE_KEY_PREFIX}-#{digest(identity)}"
  end

  private

  def dependency_content(gemfile)
    lockfile = lockfile_for(gemfile)
    [
      Digest::SHA256.file(gemfile).hexdigest,
      Digest::SHA256.file(lockfile).hexdigest,
    ]
  end

  def recipe_fingerprint
    content = CACHE_RECIPE_FILES.map do |path|
      [path, Digest::SHA256.file(absolute_path(path)).hexdigest]
    end
    digest(content)
  end

  def digest(identity)
    Digest::SHA256.hexdigest(JSON.generate(identity))
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

  def lockfile_for(gemfile)
    path = "#{gemfile}.lock"
    raise "Lockfile not found: #{relative_path(path)}" unless File.file?(path)

    path
  end

  def absolute_path(path)
    File.expand_path(path, @root)
  end

  def relative_path(path)
    expanded_path = File.expand_path(path)
    root_prefix = "#{@root}/"
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
    opts.on("--gemfiles JSON") { |value| options[:gemfiles] = JSON.parse(value) }
  end

  command = ARGV.shift
  parser.parse!(ARGV)
  raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]

  cache = InstalledBundleCache.new(base_gemfile: options[:base_gemfile], gemfiles: options.fetch(:gemfiles, []))

  case command
  when "base-key"
    raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

    puts cache.base_cache_key(image_identity: options[:image_identity])
  when "key"
    raise OptionParser::MissingArgument, "--base-cache-key" unless options[:base_cache_key]
    raise OptionParser::MissingArgument, "--gemfiles" unless options[:gemfiles]

    puts cache.cache_key(base_cache_key: options[:base_cache_key])
  else
    warn parser
    exit 1
  end
end
