require "bundler"
require "digest"
require "json"
require "optparse"

CACHE_RECIPE_FILES = %w[
  .github/actions/bundle-cache/action.yml
  .github/actions/bundle-restore/action.yml
  .github/actions/matrix-bundle-cache/action.yml
  tasks/github.rake
  tasks/matrix_bundle_cache.rb
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

def digest(identity)
  Digest::SHA256.hexdigest(JSON.generate(identity))
end

def dependency_content(gemfile)
  lockfile = "#{gemfile}.lock"
  raise "Lockfile not found: #{lockfile}" unless File.file?(lockfile)

  [
    Digest::SHA256.file(gemfile).hexdigest,
    Digest::SHA256.file(lockfile).hexdigest,
  ]
end

options = {}
parser = OptionParser.new do |opts|
  opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
  opts.on("--base-cache-key VALUE") { |value| options[:base_cache_key] = value }
  opts.on("--image VALUE") { |value| options[:image] = value }
  opts.on("--gemfiles JSON") { |value| options[:gemfiles] = JSON.parse(value) }
end

command = ARGV.shift
parser.parse!(ARGV)
raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]
cache_version = ENV.fetch("CACHE_VERSION")

case command
when "base-key"
  raise OptionParser::MissingArgument, "--image" unless options[:image]

  settings = Bundler.settings.all.sort.each_with_object({}) do |key, selected|
    selected[key] = Bundler.settings[key] if BUNDLER_SETTING_KEYS.include?(key) || key.start_with?("build.")
  end
  recipe = CACHE_RECIPE_FILES.map { |path| [path, Digest::SHA256.file(path).hexdigest] }
  identity = {
    "bundler_settings" => settings,
    "dependencies" => dependency_content(options[:base_gemfile]),
    "image" => options[:image],
    "native_build_overrides" => ENV.to_h.slice(*BUILD_ENVIRONMENT_KEYS).sort.to_h,
    "recipe" => digest(recipe),
  }
  puts "bundle-base-#{cache_version}-#{digest(identity)}"
when "matrix-key"
  raise OptionParser::MissingArgument, "--base-cache-key" unless options[:base_cache_key]
  raise OptionParser::MissingArgument, "--gemfiles" unless options[:gemfiles]

  identity = {
    "base_cache_key" => options[:base_cache_key],
    "dependencies" => options[:gemfiles].map { |gemfile| dependency_content(gemfile) }.uniq.sort,
  }
  puts "bundle-matrix-#{cache_version}-#{digest(identity)}"
else
  warn parser
  exit 1
end
