# typed: ignore

# Older Rubies don't have the MJIT header, used by the JIT compiler, so we need to use a different approach
CAN_USE_MJIT_HEADER = RUBY_VERSION >= '2.6'

def skip_building_extension?
  # We don't support JRuby for profiling, and JRuby doesn't support native extensions, so let's just skip this entire
  # thing so that JRuby users of dd-trace-rb aren't impacted.
  on_jruby = RUBY_ENGINE == 'jruby'

  # We don't officially support TruffleRuby for dd-trace-rb at all BUT let's not break adventurous customers that
  # want to give it a try.
  on_truffleruby = RUBY_ENGINE == 'truffleruby'

  # Microsoft Windows is unsupported, so let's not build the extension there.
  on_windows = Gem.win_platform?

  # On some Rubies, we require the mjit header to be present. If Ruby was installed without MJIT support, we also skip
  # building the extension.
  if expected_to_use_mjit_but_mjit_is_disabled = CAN_USE_MJIT_HEADER && RbConfig::CONFIG["MJIT_SUPPORT"] != 'yes'
    $stderr.puts(%(
+------------------------------------------------------------------------------+
| Your Ruby has been compiled without JIT support (--disable-jit-support).     |
| The profiling native extension requires a Ruby compiled with JIT support,    |
| even if the JIT is not in use by the application itself.                     |
|                                                                              |
| WARNING: Without the profiling native extension, some profiling features     |
| will not be available.                                                       |
+------------------------------------------------------------------------------+

))
  end

  # Experimental toggle to disable building the extension.
  # Disabling the extension will lead to the profiler not working in future releases.
  # If you needed to use this, please tell us why on <https://github.com/DataDog/dd-trace-rb/issues/new>.
  disabled_via_env = ENV['DD_PROFILING_NO_EXTENSION'].to_s.downcase == 'true'

  on_jruby || on_truffleruby || on_windows || expected_to_use_mjit_but_mjit_is_disabled || disabled_via_env
end

# IMPORTANT: When adding flags, remember that our customers compile with a wide range of gcc/clang versions, so
# doublecheck that what you're adding can be reasonably expected to exist on their systems.
def add_compiler_flag(flag)
  $CFLAGS << ' ' << flag
end

if skip_building_extension?
  # rubocop:disable Style/StderrPuts
  $stderr.puts(%(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension and replacing it with a no-op   |
| Makefile                                                                     |
+------------------------------------------------------------------------------+

))

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
# rubocop:enable Style/StderrPuts

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

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

if CAN_USE_MJIT_HEADER
  $defs << '-DUSE_MJIT_HEADER'

  # NOTE: This needs to come after all changes to $defs
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

  create_makefile EXTENSION_NAME
else
  # On older Rubies, we use the debase-ruby_core_source gem to get access to private VM headers.
  # This gem ships source code copies of these VM headers for the different Ruby VM versions;
  # see https://github.com/ruby-debug/debase-ruby_core_source for details

  thread_native_for_ruby_2_1 = proc { true }
  if RUBY_VERSION < '2.2'
    # This header became public in Ruby 2.2, but we need to pull it from the private headers folder for 2.1
    thread_native_for_ruby_2_1 = proc { have_header('thread_native.h') }
    $defs << '-DRUBY_2_1_WORKAROUND'
  end

  create_header

  require 'debase/ruby_core_source'
  dir_config('ruby') # allow user to pass in non-standard core include directory

  Debase::RubyCoreSource
    .create_makefile_with_core(proc { have_header('vm_core.h') && thread_native_for_ruby_2_1.call }, EXTENSION_NAME)
end
