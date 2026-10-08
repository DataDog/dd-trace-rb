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

def digest(identity)
  Digest::MD5.hexdigest(JSON.generate(identity))
end

def dependency_content(gemfile)
  [
    Digest::MD5.file(gemfile).hexdigest,
    Digest::MD5.file("#{gemfile}.lock").hexdigest,
  ]
end

cache_version = ENV.fetch("CACHE_VERSION")

case ARGV.shift
when "base-key"
  settings = Bundler.settings.all.sort.map { |key| [key, Bundler.settings[key]] }.to_h
  recipe = CACHE_RECIPE_FILES.map { |path| [path, Digest::MD5.file(path).hexdigest] }
  identity = {
    "bundler_settings" => settings,
    "dependencies" => dependency_content(ENV.fetch("BUNDLE_GEMFILE", "Gemfile")),
    "image" => ENV.fetch("IMAGE"),
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
