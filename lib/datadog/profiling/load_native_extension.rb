# frozen_string_literal: true

# This file is used to load the profiling native extension. It works in two steps:
#
# 1. Load the datadog_profiling_loader extension. This extension will be used to load the actual extension, but in
#    a special way that avoids exposing native-level code symbols. See `datadog_profiling_loader.c` for more details.
#
# 2. Use the Datadog::Profiling::Loader exposed by the datadog_profiling_loader extension to load the actual
#    profiling native extension.
#
# All code on this file is on-purpose at the top-level; this makes it so this file is executed only once,
# the first time it gets required, to avoid any issues with the native extension being initialized more than once.

begin
  require "datadog_profiling_loader.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
rescue LoadError => e
  raise LoadError,
    'Failed to load the profiling loader extension. To fix this, please remove and then reinstall datadog ' \
    "(Details: #{e.message})"
end

extension_name = "datadog_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
file_name = "#{extension_name}.#{RbConfig::CONFIG["DLEXT"]}"
full_file_path = "#{__dir__}/../../#{file_name}"

unless File.exist?(full_file_path)
  extension_dir = Gem.loaded_specs['datadog'].extension_dir
  candidate_path = "#{extension_dir}/#{file_name}"
  if File.exist?(candidate_path)
    full_file_path = candidate_path
  else # rubocop:disable Style/EmptyElse
    # We found none of the files. This is unexpected. Let's go ahead anyway, the error is going to be reported further
    # down anyway.
  end
end

init_function_name = "Init_#{extension_name.split(".").first}"

status, result = Datadog::Profiling::Loader._native_load(full_file_path, init_function_name)

raise "Failure to load #{extension_name} due to #{result}" if status == :error
