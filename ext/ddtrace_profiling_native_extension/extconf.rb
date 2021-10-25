# typed: false

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

def add_compiler_flag(flag)
  $CFLAGS << ' ' << flag
end

if skip_building_extension?
  File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  return
end

$stderr.puts(%(
+------------------------------------------------------------------------------+
| **Preparing to build the ddtrace native extension...**                       |
|                                                                              |
| If you run into any failures during this step, you can set the               |
| `DD_PROFILING_NO_EXTENSION` environment variable to `true` e.g.              |
| `$ DD_PROFILING_NO_EXTENSION=true bundle install` to skip this step.         |
|                                                                              |
| Disabling the extension will lead to the ddtrace profiling features not      |
| working in future releases.                                                  |
| If you needed to use this, please tell us why on                             |
| <https://github.com/DataDog/dd-trace-rb/issues/new> so we can fix it :\)      |
|                                                                              |
| Thanks for using ddtrace! You rock!                                          |
+------------------------------------------------------------------------------+
))

# NOTE: we MUST NOT require 'mkmf' before we check the #skip_building_extension? because the require triggers checks
# that may fail on an environment not properly setup for building Ruby extensions.
require 'mkmf'

# Gets really noisy when we include the MJIT header, let's omit it
add_compiler_flag '-Wno-unused-function'

# Allow defining variables at any point in a function
add_compiler_flag '-Wno-declaration-after-statement'

# If we forget to include a Ruby header, the function call may still appear to work, but then
# cause a segfault later. Let's ensure that never happens.
add_compiler_flag '-Werror-implicit-function-declaration'

# Older Rubies don't have the MJIT header (used by the JIT compiler, and we piggy back on it)
# TODO: Development builds of Ruby 3.1 seem to be failing on Windows; to be revisited once 3.1.0 stable is out
unless RUBY_VERSION < '2.6' || (RUBY_VERSION >= '3.1' && Gem.win_platform?)
  $defs << '-DUSE_MJIT_HEADER'
end

if RUBY_PLATFORM.include?('linux')
  # Supposedly, the correct way to do this is
  # ```
  # have_library 'pthread'
  # have_func 'pthread_getcpuclockid'
  # ```
  # but it broke the build on Windows and on older Ruby versions (2.1 and 2.2)
  # so instead we just assume that we have the function we need on Linux, and nowhere else
  $defs << '-DHAVE_PTHREAD_GETCPUCLOCKID'
end

create_header

# The MJIT header is always (afaik?) suffixed with the exact Ruby VM version,
# including patch (e.g. 2.7.2). Thus, we add to the header file a definition
# containing the exact file, so that it can be used in a #include in the C code.
header_contents =
  File.read($extconf_h)
      .sub('#endif',
           <<-EXTCONF_H.strip
#define RUBY_MJIT_HEADER "rb_mjit_min_header-#{RUBY_VERSION}.h"

#endif
           EXTCONF_H
          )
File.open($extconf_h, 'w') { |file| file.puts(header_contents) }

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
create_makefile "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
