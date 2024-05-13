#!/usr/bin/env ruby

require 'bundler/inline'

gemfile { gem 'gems', source: 'https://rubygems.org' }

require 'rubygems'
require 'gems'

image_name = ARGV[0].chomp
version = ARGV[1].chomp
version = version.delete_prefix('v') if version.start_with?('v')

candidate = Gem::Version.new(version)

if candidate.prerelease?
  warn 'No tags for pre-releases'
  exit 1
end

major, minor, = candidate.to_s.split('.')

latest_major_tag = "v#{major}"          # contains major
latest_minor_tag = "v#{major}.#{minor}" # contains major, minor

tags = []

gem_name = 'datadog'

# Check if the candidate is larger than public latest version
tags << 'latest' if candidate > Gem::Version.new(Gems.latest_version(gem_name).fetch('version'))
tags << latest_major_tag
tags << latest_minor_tag
tags << "v#{candidate}"

destinations = tags.map { |tag| "#{image_name}:#{tag}" }

$stdout.puts destinations.join(',')
