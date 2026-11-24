#!/usr/bin/env ruby

if ENV["DD_DEMO_ENV_GEM_LOCAL_DATADOG"]
  puts "\n== Building profiler native extension =="

  # Compile against the app's resolved dependencies, without the development Rakefile.
  raise "Failure to install application dependencies" unless system("bundle", "install")

  success = system(
    "bundle", "exec", "ruby", "-rrubygems/ext", "-e",
    'Gem::Ext::Builder.new(Gem.loaded_specs.fetch("datadog")).build_extensions',
  )
  raise "Failure to compile profiler native extension" unless success
else
  puts "\n== Skipping build of profiler native extension, no DD_DEMO_ENV_GEM_LOCAL_DATADOG set =="
end
