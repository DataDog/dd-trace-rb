#!/usr/bin/env ruby

require "json"
require "optparse"
require "pathname"
require_relative "installed_bundle_cache"

options = {
  root: Pathname.pwd,
  matrix: "Matrixfile",
  strategy: "full",
  installed_path: "/usr/local/bundle",
}

parser = OptionParser.new do |opts|
  opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
  opts.on("--matrix PATH") { |value| options[:matrix] = value }
  opts.on("--cache-schema VALUE") { |value| options[:cache_schema] = value }
  opts.on("--image-identity VALUE") { |value| options[:image_identity] = value }
  opts.on("--base-cache-key VALUE") { |value| options[:base_cache_key] = value }
  opts.on("--strategy VALUE") { |value| options[:strategy] = value }
  opts.on("--installed-path PATH") { |value| options[:installed_path] = value }
  opts.on("--snapshot PATH") { |value| options[:snapshot] = value }
  opts.on("--destination PATH") { |value| options[:destination] = value }
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
  strategy: options[:strategy],
  installed_path: options[:installed_path],
)

case command
when "manifest"
  raise OptionParser::MissingArgument, "--cache-schema" unless options[:cache_schema]
  raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

  puts JSON.pretty_generate(
    cache.to_h(
      cache_schema: options[:cache_schema],
      image_identity: options[:image_identity],
      base_cache_key: options[:base_cache_key],
    )
  )
when "install"
  cache.install(jobs: options.fetch(:jobs, 8))
when "check"
  cache.check
when "snapshot"
  raise OptionParser::MissingArgument, "--snapshot" unless options[:snapshot]

  cache.write_snapshot(options[:snapshot])
when "extract-delta"
  raise OptionParser::MissingArgument, "--snapshot" unless options[:snapshot]
  raise OptionParser::MissingArgument, "--destination" unless options[:destination]

  cache.extract_delta(base_snapshot_path: options[:snapshot], destination: options[:destination])
else
  warn parser
  exit 1
end
