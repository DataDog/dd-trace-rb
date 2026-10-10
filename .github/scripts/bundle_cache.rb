# Runs without bundle exec.
require "bundler"
require "digest"
require "json"

# Changing these might affect caching output
CACHE_LOGIC_FILES = %w[
  .github/actions/bundle-cache/action.yml
  .github/actions/bundle-matrix-cache/action.yml
  .github/actions/bundle-restore/action.yml
  tasks/github.rake
  .github/scripts/bundle_cache.rb
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

version = ENV["CACHE_VERSION"]
version = "0" if version.empty?

settings = Bundler.settings.all.sort.map { |key| [key, Bundler.settings[key]] }.to_h
recipe = CACHE_LOGIC_FILES.map { |path| [path, Digest::MD5.file(path).hexdigest] }
image = ENV.fetch("IMAGE")
identity = {
  "bundler_settings" => settings,
  "image" => image,
}
core_dependencies = dependency_content(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"))

cache_key = case ARGV.shift
when "core"
  identity = {
    "bundler_settings" => settings,
    "dependencies" => core_dependencies,
    "image" => image,
    "recipe" => digest(recipe),
  }
  "bundle-core-v#{version}-#{digest(identity)}"
when "matrix"
  dependencies = JSON.parse(ENV["GEMFILES"]).map { |gemfile| dependency_content(gemfile) }
  dependencies = (dependencies + [core_dependencies]).uniq.sort
  image_prefix = "bundle-matrix-v#{version}-#{digest(identity)}-"
  logic_prefix = "#{image_prefix}#{digest(recipe)}-"
  "#{logic_prefix}#{digest(dependencies)}"
else
  abort "Expected core or matrix"
end

puts "cache-key=#{cache_key}"
if logic_prefix
  puts "restore-keys<<EOF"
  puts logic_prefix
  puts image_prefix
  puts "EOF"
end
