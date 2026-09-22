#!/usr/bin/env ruby

require "json"
require "optparse"
require "pathname"
require_relative "installed_bundle_cache"

options = {
  root: Pathname.pwd,
  matrix: "Matrixfile",
}

parser = OptionParser.new do |opts|
  opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
  opts.on("--matrix PATH") { |value| options[:matrix] = value }
  opts.on("--cache-schema VALUE") { |value| options[:cache_schema] = value }
  opts.on("--image-identity VALUE") { |value| options[:image_identity] = value }
  opts.on("--jobs COUNT", Integer) { |value| options[:jobs] = value }
end

command = ARGV.shift
parser.parse!(ARGV)
raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]

matrix = GithubMatrix.new(matrix_path: options[:matrix], fallback_gemfile: options[:base_gemfile])
cache = InstalledBundleCache.new(
  root: options[:root],
  base_gemfile: options[:base_gemfile],
  matrix: matrix,
)

case command
when "manifest"
  raise OptionParser::MissingArgument, "--cache-schema" unless options[:cache_schema]
  raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

  puts JSON.pretty_generate(
    cache.to_h(
      cache_schema: options[:cache_schema],
      image_identity: options[:image_identity],
    )
  )
when "install"
  cache.install(jobs: options.fetch(:jobs, 8))
when "check"
  cache.check
else
  warn parser
  exit 1
end
