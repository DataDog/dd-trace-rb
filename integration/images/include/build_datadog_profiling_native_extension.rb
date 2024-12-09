#!/usr/bin/env ruby

if local_gem_path = ENV['DD_DEMO_ENV_GEM_LOCAL_DATADOG']
  puts "\n== Building profiler native extension =="
  success =
    system("export BUNDLE_GEMFILE=#{local_gem_path}/Gemfile && cd #{local_gem_path} && bundle install && bundle exec rake clean compile")
  raise 'Failure to compile profiler native extension' unless success
else
  puts "\n== Skipping build of profiler native extension, no DD_DEMO_ENV_GEM_LOCAL_DATADOG set =="
end
