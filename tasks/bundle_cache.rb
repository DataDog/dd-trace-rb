# Runs without bundle exec; Bundler is loaded only for its settings API.
require "bundler"
require "digest"
require "json"

# Partial restores may reuse older logic; bump CACHE_VERSION for incompatible cache layouts.
CACHE_LOGIC_FILES = %w[
  .github/actions/bundle-cache/action.yml
  .github/actions/bundle-matrix-cache/action.yml
  .github/actions/bundle-restore/action.yml
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

cache_version = ENV.fetch("CACHE_VERSION", "0")
cache_version = "0" if cache_version.empty?

settings = Bundler.settings.all.sort.map { |key| [key, Bundler.settings[key]] }.to_h
recipe = CACHE_LOGIC_FILES.map { |path| [path, Digest::MD5.file(path).hexdigest] }
image = ENV.fetch("IMAGE")
identity = {
  "bundler_settings" => settings,
  "image" => image,
}
core_dependencies = dependency_content(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"))

case ARGV.shift
when "core-key"
  identity = {
    "bundler_settings" => settings,
    "dependencies" => core_dependencies,
    "image" => image,
    "recipe" => digest(recipe),
  }
  puts "bundle-core-v#{cache_version}-#{digest(identity)}"
when "matrix-key"
  dependencies = JSON.parse(ENV["GEMFILES"]).map { |gemfile| dependency_content(gemfile) }
  dependencies = (dependencies + [core_dependencies]).uniq.sort
  puts "bundle-matrix-#{cache_version}-#{digest(identity)}-#{digest(recipe)}-#{digest(dependencies)}"
else
  abort "Expected core-key or matrix-key"
end
