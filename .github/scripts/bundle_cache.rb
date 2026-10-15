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
logic = digest(CACHE_LOGIC_FILES.map { |path| [path, Digest::MD5.file(path).hexdigest] })
image = ENV.fetch("IMAGE")
core_dependencies = dependency_content(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"))

type = ARGV.shift
key_prefix = "bundle-#{type}-v#{version}-"

dependencies = case type
when "core"
  [core_dependencies]
when "matrix"
  JSON.parse(ENV["GEMFILES"]).map { |gemfile| dependency_content(gemfile) } + [core_dependencies]
else
  abort "Expected core or matrix"
end

identity = {
  "bundler_settings" => settings,
  "image" => image,
}
dependencies = dependencies.uniq.sort
image_prefix = "#{key_prefix}#{digest(identity)}-"
logic_prefix = "#{image_prefix}#{logic}-"

puts "cache-key=#{logic_prefix}#{digest(dependencies)}"
puts "restore-keys<<EOF"
puts logic_prefix
puts image_prefix
puts "EOF"
