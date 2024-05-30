#!/usr/bin/env ruby

require 'bundler/inline'

gemfile { gem 'gems', source: 'https://rubygems.org' }

require 'rubygems'
require 'gems'

image_name = ARGV[0].chomp
version = ARGV[1].chomp
version = version.delete_prefix('v') if version.start_with?('v')

candidate = Gem::Version.new(version)
versions = Gems.versions('datadog').map { |h| Gem::Version.new(h['number']) }

# Make sure candidate has already been published to 'https://rubygems.org'
unless versions.include?(candidate)
  warn "Version #{candidate} not found in RubyGems"
  exit 1
end

# Skip pre-releases
if candidate.prerelease?
  warn 'No tags for pre-releases'
  exit 1
end

major, minor, = candidate.to_s.split('.')
current_major_versions = versions.select { |v| v.to_s.start_with?("#{major}.") }

tags = []

# Disable tagging 'latest' for now avoid crossing major versions
# tags << 'latest'    if versions.all? { |v| candidate >= v }
tags << "v#{major}" if current_major_versions.all? { |v| candidate >= v }
tags << "v#{major}.#{minor}"
tags << "v#{candidate}"

# $stdout.puts "tags: #{tags}" # Uncomment for debugging

destinations = tags.map { |tag| "#{image_name}:#{tag}" }
$stdout.puts destinations.join(',')
