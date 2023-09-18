#!/usr/bin/env ruby

if local_gem_path = ENV['DD_DEMO_ENV_GEM_LOCAL_DDTRACE']
  if RUBY_VERSION.start_with?('2.1.', '2.2.', '3.3.')
    puts "\n== Skipping build of profiler native extension on Ruby 2.1/2.2 + 3.3 =="
  else
    puts "\n== Building profiler native extension =="
    success =
      system("export BUNDLE_GEMFILE=#{local_gem_path}/Gemfile && cd #{local_gem_path} && bundle install && bundle exec rake clean compile")
    raise 'Failure to compile profiler native extension' unless success
  end
else
  puts "\n== Skipping build of profiler native extension, no DD_DEMO_ENV_GEM_LOCAL_DDTRACE set =="
end
