#!/usr/bin/env ruby

require "json"
require "optparse"
require_relative "installed_bundle_cache"

options = {}

parser = OptionParser.new do |opts|
  opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
  opts.on("--base-cache-key VALUE") { |value| options[:base_cache_key] = value }
  opts.on("--image-identity VALUE") { |value| options[:image_identity] = value }
end

command = ARGV.shift
parser.parse!(ARGV)
raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]

cache = InstalledBundleCache.new(base_gemfile: options[:base_gemfile])

case command
when "manifest"
  raise OptionParser::MissingArgument, "--base-cache-key" unless options[:base_cache_key]
  raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

  puts JSON.pretty_generate(
    cache.to_h(
      image_identity: options[:image_identity],
      base_cache_key: options[:base_cache_key],
    )
  )
when "install-appraisals"
  cache.install_appraisals
when "check"
  cache.check
else
  warn parser
  exit 1
end
