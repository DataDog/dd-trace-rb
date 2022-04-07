# typed: ignore

# rubocop:disable Style/StderrPuts
# rubocop:disable Style/GlobalVars

require_relative 'native_extension_helpers'

SKIPPED_REASON_FILE = "#{__dir__}/skipped_reason.txt".freeze
# Not a problem if the file doesn't exist or we can't delete it
File.delete(SKIPPED_REASON_FILE) rescue nil

def skip_building_extension!(reason)
  $stderr.puts(Datadog::Profiling::NativeExtensionHelpers::Supported.failure_banner_for(**reason))
  File.write(
    SKIPPED_REASON_FILE,
    Datadog::Profiling::NativeExtensionHelpers::Supported.render_skipped_reason_file(**reason),
  )

  File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  exit
end

unless Datadog::Profiling::NativeExtensionHelpers::Supported.supported?
  skip_building_extension!(Datadog::Profiling::NativeExtensionHelpers::Supported.unsupported_reason)
end

$stderr.puts(%(
+------------------------------------------------------------------------------+
| ** Preparing to build the ddtrace profiling native extension... **           |
|                                                                              |
| If you run into any failures during this step, you can set the               |
| `DD_PROFILING_NO_EXTENSION` environment variable to `true` e.g.              |
| `$ DD_PROFILING_NO_EXTENSION=true bundle install` to skip this step.         |
|                                                                              |
| If you disable this extension, the Datadog Continuous Profiler will          |
| not be available, but all other ddtrace features will work fine!             |
|                                                                              |
| If you needed to use this, please tell us why on                             |
| <https://github.com/DataDog/dd-trace-rb/issues/new> so we can fix it :\)      |
|                                                                              |
| Thanks for using ddtrace! You rock!                                          |
+------------------------------------------------------------------------------+

))

# NOTE: we MUST NOT require 'mkmf' before we check the #skip_building_extension? because the require triggers checks
# that may fail on an environment not properly setup for building Ruby extensions.
require 'mkmf'

# mkmf on modern Rubies actually has an append_cflags that does something similar
# (see https://github.com/ruby/ruby/pull/5760), but as usual we need a bit more boilerplate to deal with legacy Rubies
def add_compiler_flag(flag)
  if try_cflags(flag)
    $CFLAGS << ' ' << flag
  else
    $stderr.puts("WARNING: '#{flag}' not accepted by compiler, skipping it")
  end
end

# Older gcc releases may not default to C99 and we need to ask for this. This is also used:
# * by upstream Ruby -- search for gnu99 in the codebase
# * by msgpack, another ddtrace dependency
#   (https://github.com/msgpack/msgpack-ruby/blob/18ce08f6d612fe973843c366ac9a0b74c4e50599/ext/msgpack/extconf.rb#L8)
add_compiler_flag '-std=gnu99'

# Gets really noisy when we include the MJIT header, let's omit it
add_compiler_flag '-Wno-unused-function'

# Allow defining variables at any point in a function
add_compiler_flag '-Wno-declaration-after-statement'

# If we forget to include a Ruby header, the function call may still appear to work, but then
# cause a segfault later. Let's ensure that never happens.
add_compiler_flag '-Werror-implicit-function-declaration'

# The native extension is not intended to expose any symbols/functions for other native libraries to use;
# the sole exception being `Init_ddtrace_profiling_native_extension` which needs to be visible for Ruby to call it when
# it `dlopen`s the library.
#
# By setting this compiler flag, we tell it to assume that everything is private unless explicitly stated.
# For more details see https://gcc.gnu.org/wiki/Visibility
add_compiler_flag '-fvisibility=hidden'

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

# On older Rubies, we need to use a backported version of this function. See private_vm_api_access.h for details.
if RUBY_VERSION < '3'
  $defs << '-DUSE_BACKPORTED_RB_PROFILE_FRAME_METHOD_NAME'
end

# On older Rubies, we need to use rb_thread_t instead of rb_execution_context_t
if RUBY_VERSION < '2.5'
  $defs << '-DUSE_THREAD_INSTEAD_OF_EXECUTION_CONTEXT'
end

# For REALLY OLD Rubies...
if RUBY_VERSION < '2.3'
  # ...there was no rb_time_timespec_new function
  $defs << '-DNO_RB_TIME_TIMESPEC_NEW'
end

# If we got here, libddprof is available and loaded
ENV['PKG_CONFIG_PATH'] = "#{ENV['PKG_CONFIG_PATH']}:#{Libddprof.pkgconfig_folder}"
unless pkg_config('ddprof_ffi_with_rpath')
  skip_building_extension!(Datadog::Profiling::NativeExtensionHelpers::Supported::FAILED_TO_CONFIGURE_LIBDDPROF)
end

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

if Datadog::Profiling::NativeExtensionHelpers::CAN_USE_MJIT_HEADER
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
    skip_building_extension!(Datadog::Profiling::NativeExtensionHelpers::Supported::COMPILATION_BROKEN)
  end
  MakeMakefile::COMMON_HEADERS = original_common_headers

  $defs << "-DRUBY_MJIT_HEADER='\"#{mjit_header_file_name}\"'"

  # NOTE: This needs to come after all changes to $defs
  create_header

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
    .create_makefile_with_core(
      proc { have_header('vm_core.h') && have_header('iseq.h') && thread_native_for_ruby_2_1.call },
      EXTENSION_NAME,
    )
end

# rubocop:enable Style/GlobalVars
# rubocop:enable Style/StderrPuts
