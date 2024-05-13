#!/usr/bin/env ruby

require 'rubygems'

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

# `ddtrace` is the gem name on 1.x-stable branch, releasing from this branch means it won't be tagged with `latest`
#
# `latest` tag will be carried over by 2.x version of the gem named `datadog` on `master` branch
tags << latest_major_tag
tags << latest_minor_tag
tags << "v#{candidate}"

destinations = tags.map { |tag| "#{image_name}:#{tag}" }

$stdout.puts destinations.join(',')
