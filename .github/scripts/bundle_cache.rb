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
recipe = digest(CACHE_LOGIC_FILES.map { |path| [path, Digest::MD5.file(path).hexdigest] })
image = ENV.fetch("IMAGE")
identity = {
  "bundler_settings" => settings,
  "image" => image,
}
core_dependencies = dependency_content(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"))

type = ARGV.shift

case type
when "core"
  identity = {
    "bundler_settings" => settings,
    "dependencies" => core_dependencies,
    "image" => image,
    "recipe" => recipe,
  }
when "matrix"
  dependencies = JSON.parse(ENV["GEMFILES"]).map { |gemfile| dependency_content(gemfile) }
  dependencies = (dependencies + [core_dependencies]).uniq.sort
else
  abort "Expected core or matrix"
end

cache_key = "bundle-#{type}-v#{version}-#{digest(identity)}"
if dependencies
  image_prefix = "#{cache_key}-"
  logic_prefix = "#{image_prefix}#{recipe}-"
  cache_key = "#{logic_prefix}#{digest(dependencies)}"
end

puts "cache-key=#{cache_key}"
if logic_prefix
  puts "restore-keys<<EOF"
  puts logic_prefix
  puts image_prefix
  puts "EOF"
end
