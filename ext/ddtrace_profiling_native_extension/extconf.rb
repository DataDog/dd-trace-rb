require 'mkmf'

# We don't support JRuby for profiling, and JRuby doesn't support native extensions, so let's just skip this entire
# thing so that JRuby users of dd-trace-rb aren't impacted.
if RUBY_ENGINE == 'jruby'
  File.write('Makefile', dummy_makefile($srcdir).join) # rubocop:disable Style/GlobalVars
  return
end

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
create_makefile "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
