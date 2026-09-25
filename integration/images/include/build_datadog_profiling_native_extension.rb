#!/usr/bin/env ruby

if local_gem_path = ENV['DD_DEMO_ENV_GEM_LOCAL_DATADOG']
  puts "\n== Building profiler native extension =="
  success =
    system("cd #{local_gem_path} && ruby -r./tasks/prelock -e 'Prelock.call(\"Gemfile\")' && bundle install && bundle exec rake clean compile")
  raise 'Failure to compile profiler native extension' unless success
else
  puts "\n== Skipping build of profiler native extension, no DD_DEMO_ENV_GEM_LOCAL_DATADOG set =="
end
