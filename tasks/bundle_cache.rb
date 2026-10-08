require "bundler"
require "digest"
require "json"

CACHE_RECIPE_FILES = %w[
  .github/actions/prepare-base-bundle/action.yml
  .github/actions/prepare-matrix-bundle/action.yml
  .github/actions/restore-bundle-cache/action.yml
  tasks/github.rake
  tasks/bundle_cache.rb
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
  [
    Digest::SHA256.file(gemfile).hexdigest,
    Digest::SHA256.file("#{gemfile}.lock").hexdigest,
  ]
end

cache_version = ENV.fetch("CACHE_VERSION")

case ARGV.shift
when "base-key"
  settings = Bundler.settings.all.sort.each_with_object({}) do |key, selected|
    selected[key] = Bundler.settings[key] if BUNDLER_SETTING_KEYS.include?(key) || key.start_with?("build.")
  end
  recipe = CACHE_RECIPE_FILES.map { |path| [path, Digest::SHA256.file(path).hexdigest] }
  identity = {
    "bundler_settings" => settings,
    "dependencies" => dependency_content(ENV.fetch("BUNDLE_GEMFILE", "Gemfile")),
    "image" => ENV.fetch("IMAGE"),
    "native_build_overrides" => ENV.to_h.slice(*BUILD_ENVIRONMENT_KEYS).sort.to_h,
    "recipe" => digest(recipe),
  }
  puts "bundle-base-#{cache_version}-#{digest(identity)}"
when "matrix-key"
  identity = {
    "base_cache_key" => ARGV.fetch(0),
    "dependencies" => JSON.parse(ENV.fetch("GEMFILES")).map { |gemfile| dependency_content(gemfile) }.uniq.sort,
  }
  puts "bundle-matrix-#{cache_version}-#{digest(identity)}"
else
  abort "Expected base-key or matrix-key"
end
