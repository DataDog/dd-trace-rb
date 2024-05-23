#!/usr/bin/env ruby

require 'bundler/inline'

gemfile { gem 'gems', source: 'https://rubygems.org' }

require 'rubygems'
require 'gems'

version = ARGV[0].chomp
version = version.delete_prefix('v') if version.start_with?('v')

candidate = Gem::Version.new(version)

retry_count = 0
max_retries = 60
interval = 60

loop do
  versions = Gems.versions('ddtrace').map { |h| Gem::Version.new(h['number']) }

  if versions.include?(candidate)
    puts "Gem version #{candidate} found!"
    exit 0
  else
    retry_count += 1
    puts "Attempt(#{retry_count}):  Gem 'ddtrace' version '#{candidate}' not found."

    if retry_count >= max_retries
      puts "Max retries(#{max_retries}) reached, stopping..."
      exit 1
    else
      puts "Retrying in #{interval} seconds..."
      sleep interval
    end
  end
end
