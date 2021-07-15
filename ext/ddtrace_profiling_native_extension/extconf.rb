def skip_building_extension?
  # We don't support JRuby for profiling, and JRuby doesn't support native extensions, so let's just skip this entire
  # thing so that JRuby users of dd-trace-rb aren't impacted.
  on_jruby = RUBY_ENGINE == 'jruby'

  # Experimental toggle to disable building the extension.
  # Disabling the extension will lead to the profiler not working in future releases.
  # If you needed to use this, please tell us why on <https://github.com/DataDog/dd-trace-rb/issues/new>.
  disabled_via_env = ENV['DD_PROFILING_NO_EXTENSION'].to_s.downcase == 'true'

  on_jruby || disabled_via_env
end

if skip_building_extension?
  File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  return
end

# NOTE: we MUST NOT require 'mkmf' before we check the #skip_building_extension? because the require triggers checks
# that may fail on an environment not properly setup for building Ruby extensions.
require 'mkmf'

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
create_makefile "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
