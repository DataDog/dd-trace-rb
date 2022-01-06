# typed: ignore
# rubocop:disable Style/StderrPuts

# Older Rubies don't have the MJIT header, used by the JIT compiler, so we need to use a different approach
CAN_USE_MJIT_HEADER = RUBY_VERSION >= '2.6'

def on_jruby?
  # We don't support JRuby for profiling, and JRuby doesn't support native extensions, so let's just skip this entire
  # thing so that JRuby users of dd-trace-rb aren't impacted.
  RUBY_ENGINE == 'jruby'
end

def on_truffleruby?
  # We don't officially support TruffleRuby for dd-trace-rb at all BUT let's not break adventurous customers that
  # want to give it a try.
  RUBY_ENGINE == 'truffleruby'
end

def on_windows?
  # Microsoft Windows is unsupported, so let's not build the extension there.
  Gem.win_platform?
end

def expected_to_use_mjit_but_mjit_is_disabled?
  # On some Rubies, we require the mjit header to be present. If Ruby was installed without MJIT support, we also skip
  # building the extension.
  mjit_disabled = CAN_USE_MJIT_HEADER && RbConfig::CONFIG['MJIT_SUPPORT'] != 'yes'

  if mjit_disabled
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

  mjit_disabled
end

def disabled_via_env?
  # Experimental toggle to disable building the extension.
  # Disabling the extension will lead to the profiler not working in future releases.
  # If you needed to use this, please tell us why on <https://github.com/DataDog/dd-trace-rb/issues/new>.
  ENV['DD_PROFILING_NO_EXTENSION'].to_s.downcase == 'true'
end

def skip_building_extension?
  disabled_via_env? || on_jruby? || on_truffleruby? || on_windows? || expected_to_use_mjit_but_mjit_is_disabled?
end

# IMPORTANT: When adding flags, remember that our customers compile with a wide range of gcc/clang versions, so
# doublecheck that what you're adding can be reasonably expected to work on their systems.
def add_compiler_flag(flag)
  $CFLAGS << ' ' << flag
end

def skip_building_extension!
  File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  exit
end

if skip_building_extension?
  $stderr.puts(%(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension and replacing it with a no-op   |
| Makefile                                                                     |
+------------------------------------------------------------------------------+

))
  skip_building_extension!
end

$stderr.puts(%(
+------------------------------------------------------------------------------+
| ** Preparing to build the ddtrace native extension... **                     |
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
  mjit_header_file_name = "rb_mjit_min_header-#{RUBY_VERSION}.h"

  # Validate that the mjit header can actually be compiled on this system. We learned via
  # https://github.com/DataDog/dd-trace-rb/issues/1799 and https://github.com/DataDog/dd-trace-rb/issues/1792
  # that even if the header seems to exist, it may not even compile.
  # `have_macro` actually tries to compile a file that mentions the given macro, so if this passes, we should be good to
  # use the MJIT header.
  # Finally, the `COMMON_HEADERS` conflict with the MJIT header so we need to temporarily disable them for this check.
  original_common_headers = MakeMakefile::COMMON_HEADERS
  MakeMakefile::COMMON_HEADERS = ''.freeze
  unless have_macro('RUBY_MJIT_H', mjit_header_file_name)
    $stderr.puts(%(
+------------------------------------------------------------------------------+
| WARNING: Unable to compile a needed component for ddtrace native extension.  |
| Your C compiler or Ruby VM just-in-time compiler seems to be broken.         |
|                                                                              |
| You will be NOT be able to use ddtrace profiling features,                   |
| but all other features will work fine!                                       |
|                                                                              |
| For help solving this issue, please contact Datadog support at               |
| <https://docs.datadoghq.com/help/>.                                          |
+------------------------------------------------------------------------------+

))
    skip_building_extension!
  end
  MakeMakefile::COMMON_HEADERS = original_common_headers

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
#define RUBY_MJIT_HEADER "#{mjit_header_file_name}"

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
# rubocop:enable Style/StderrPuts
