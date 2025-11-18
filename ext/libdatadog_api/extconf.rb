# rubocop:disable Style/StderrPuts
# rubocop:disable Style/GlobalVars

require 'rubygems'
require_relative '../libdatadog_extconf_helpers'

def skip_building_extension!(reason)
  $stderr.puts(
    "WARN: Skipping build of libdatadog_api (#{reason}). Some functionality will not be available."
  )

  fail_install_if_missing_extension = ENV['DD_FAIL_INSTALL_IF_MISSING_EXTENSION'].to_s.strip.downcase == 'true'

  if fail_install_if_missing_extension
    require 'mkmf'
    Logging.message("[datadog] Failure cause: #{reason}")
  else
    File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  end

  exit
end

if ENV['DD_NO_EXTENSION'].to_s.strip.downcase == 'true'
  skip_building_extension!('the `DD_NO_EXTENSION` environment variable is/was set to `true` during installation')
end
skip_building_extension!('current Ruby VM is not supported') if RUBY_ENGINE != 'ruby'
skip_building_extension!('Microsoft Windows is not supported') if Gem.win_platform?

libdatadog_issue = Datadog::LibdatadogExtconfHelpers.load_libdatadog_or_get_issue
skip_building_extension!("issue setting up `libdatadog` gem: #{libdatadog_issue}") if libdatadog_issue

require 'mkmf'

# Because we can't control what compiler versions our customers use, shipping with -Werror by default is a no-go.
# But we can enable it in CI, so that we quickly spot any new warnings that just got introduced.
append_cflags '-Werror' if ENV['DATADOG_GEM_CI'] == 'true'

# Older gcc releases may not default to C99 and we need to ask for this. This is also used:
# * by upstream Ruby -- search for gnu99 in the codebase
# * by msgpack, another datadog gem dependency
#   (https://github.com/msgpack/msgpack-ruby/blob/18ce08f6d612fe973843c366ac9a0b74c4e50599/ext/msgpack/extconf.rb#L8)
append_cflags '-std=gnu99'

# Gets really noisy when we include the MJIT header, let's omit it (TODO: Use #pragma GCC diagnostic instead?)
append_cflags "-Wno-unused-function"

# Allow defining variables at any point in a function
append_cflags '-Wno-declaration-after-statement'

# If we forget to include a Ruby header, the function call may still appear to work, but then
# cause a segfault later. Let's ensure that never happens.
append_cflags '-Werror-implicit-function-declaration'

# Note: -Wunused-parameter is added later for Ruby 3.3+ compatibility
# See comment near line 240 about why this flag breaks header detection on Ruby 3.3

# The native extension is not intended to expose any symbols/functions for other native libraries to use;
# the sole exception being `Init_libdatadog_api` which needs to be visible for Ruby to call it when
# it `dlopen`s the library.
#
# By setting this compiler flag, we tell it to assume that everything is private unless explicitly stated.
# For more details see https://gcc.gnu.org/wiki/Visibility
append_cflags '-fvisibility=hidden'

# Avoid legacy C definitions
append_cflags '-Wold-style-definition'

# Enable all other compiler warnings
append_cflags '-Wall'
append_cflags '-Wextra'

if ENV['DDTRACE_DEBUG'] == 'true'
  $defs << '-DDD_DEBUG'
  CONFIG['optflags'] = '-O0'
  CONFIG['debugflags'] = '-ggdb3'
end

# If we got here, libdatadog is available and loaded
ENV['PKG_CONFIG_PATH'] = "#{ENV["PKG_CONFIG_PATH"]}:#{Libdatadog.pkgconfig_folder}"
Logging.message("[datadog] PKG_CONFIG_PATH set to #{ENV["PKG_CONFIG_PATH"].inspect}\n")
$stderr.puts("Using libdatadog #{Libdatadog::VERSION} from #{Libdatadog.pkgconfig_folder}")

unless pkg_config('datadog_profiling_with_rpath')
  Logging.message("[datadog] Ruby detected the pkg-config command is #{$PKGCONFIG.inspect}\n")

  if Datadog::LibdatadogExtconfHelpers.pkg_config_missing?
    skip_building_extension!('the `pkg-config` system tool is missing')
  else
    skip_building_extension!('there was a problem in setting up the `libdatadog` dependency')
  end
end

# See comments on the helper methods being used for why we need to additionally set this.
# The extremely excessive escaping around ORIGIN below seems to be correct and was determined after a lot of
# experimentation. We need to get these special characters across a lot of tools untouched...
extra_relative_rpaths = [
  Datadog::LibdatadogExtconfHelpers.libdatadog_folder_relative_to_native_lib_folder(current_folder: __dir__),
  *Datadog::LibdatadogExtconfHelpers.libdatadog_folder_relative_to_ruby_extensions_folders,
]
extra_relative_rpaths.each { |folder| $LDFLAGS += " -Wl,-rpath,$$$\\\\{ORIGIN\\}/#{folder.to_str}" }
Logging.message("[datadog] After pkg-config $LDFLAGS were set to: #{$LDFLAGS.inspect}\n")

# Enable access to Ruby VM internal headers for crashtracker stack walking
# Ruby version compatibility definitions similar to profiling extension

# On Ruby 3.5, we can't ask the object_id from IMEMOs (https://github.com/ruby/ruby/pull/13347)
$defs << "-DNO_IMEMO_OBJECT_ID" unless RUBY_VERSION < "3.5"

# On Ruby 2.5 and 3.3, this symbol was not visible. It is on 2.6 to 3.2, as well as 3.4+
$defs << "-DNO_RB_OBJ_INFO" if RUBY_VERSION.start_with?("2.5", "3.3")

# On older Rubies, rb_postponed_job_preregister/rb_postponed_job_trigger did not exist
$defs << "-DNO_POSTPONED_TRIGGER" if RUBY_VERSION < "3.3"

# On older Rubies, M:N threads were not available
$defs << "-DNO_MN_THREADS_AVAILABLE" if RUBY_VERSION < "3.3"

# On older Rubies, we did not need to include the ractor header (this was built into the MJIT header)
$defs << "-DNO_RACTOR_HEADER_INCLUDE" if RUBY_VERSION < "3.3"

# On older Rubies, some of the Ractor internal APIs were directly accessible
$defs << "-DUSE_RACTOR_INTERNAL_APIS_DIRECTLY" if RUBY_VERSION < "3.3"

# On older Rubies, there was no GVL instrumentation API and APIs created to support it
$defs << "-DNO_GVL_INSTRUMENTATION" if RUBY_VERSION < "3.2"

# Supporting GVL instrumentation on 3.2 needs some workarounds
$defs << "-DUSE_GVL_PROFILING_3_2_WORKAROUNDS" if RUBY_VERSION.start_with?("3.2")

# On older Rubies, there was no struct rb_native_thread. See private_vm_api_acccess.c for details.
$defs << "-DNO_RB_NATIVE_THREAD" if RUBY_VERSION < "3.2"

# On older Rubies, there was no struct rb_thread_sched (it was struct rb_global_vm_lock_struct)
$defs << "-DNO_RB_THREAD_SCHED" if RUBY_VERSION < "3.2"

# On older Rubies, the first_lineno inside a location was a VALUE and not a int (https://github.com/ruby/ruby/pull/6430)
$defs << "-DNO_INT_FIRST_LINENO" if RUBY_VERSION < "3.2"

# On older Rubies, there was no tid member in the internal thread structure
$defs << "-DNO_THREAD_TID" if RUBY_VERSION < "3.1"

# On older Rubies, there was no jit_return member on the rb_control_frame_t struct
$defs << "-DNO_JIT_RETURN" if RUBY_VERSION < "3.1"

# On older Rubies, there are no Ractors
$defs << "-DNO_RACTORS" if RUBY_VERSION < "3"

# On older Rubies, rb_imemo_name did not exist
$defs << "-DNO_IMEMO_NAME" if RUBY_VERSION < "3"

# On older Rubies, objects would not move
$defs << "-DNO_T_MOVED" if RUBY_VERSION < "2.7"

# On older Rubies, rb_global_vm_lock_struct did not include the owner field
$defs << "-DNO_GVL_OWNER" if RUBY_VERSION < "2.6"

# On older Rubies, there was no thread->invoke_arg
$defs << "-DNO_THREAD_INVOKE_ARG" if RUBY_VERSION < "2.6"

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}".freeze

# Setup Ruby VM private headers access
CAN_USE_MJIT_HEADER = RUBY_VERSION.start_with?("2.6", "2.7", "3.0.", "3.1.", "3.2.")

if CAN_USE_MJIT_HEADER
  mjit_header_file_name = "rb_mjit_min_header-#{RUBY_VERSION}.h"

  # Validate that the mjit header can actually be compiled on this system. We learned via
  # https://github.com/DataDog/dd-trace-rb/issues/1799 and https://github.com/DataDog/dd-trace-rb/issues/1792
  # that even if the header seems to exist, it may not even compile.
  # `have_macro` actually tries to compile a file that mentions the given macro, so if this passes, we should be good to
  # use the MJIT header.
  # Finally, the `COMMON_HEADERS` conflict with the MJIT header so we need to temporarily disable them for this check.
  original_common_headers = MakeMakefile::COMMON_HEADERS
  MakeMakefile::COMMON_HEADERS = "".freeze
  unless have_macro("RUBY_MJIT_H", mjit_header_file_name)
    skip_building_extension!('MJIT header compilation failed - required for crashtracker stack walking')
  end
  MakeMakefile::COMMON_HEADERS = original_common_headers

  $defs << "-DRUBY_MJIT_HEADER='\"#{mjit_header_file_name}\"'"

  # NOTE: This needs to come after all changes to $defs
  create_header

  # Note: -Wunused-parameter flag is intentionally added here only after MJIT header validation
  # This is because adding this flag before checking internal VM headers causes those checks to fail
  # on some Ruby versions (e.g. 3.3) due to warnings, not because the headers are unavailable
  append_cflags "-Wunused-parameter"

  create_makefile(EXTENSION_NAME)
else
  # The MJIT header was introduced on 2.6 and removed on 3.3; for other Rubies we rely on
  # the datadog-ruby_core_source gem to get access to private VM headers.
  # This gem ships source code copies of these VM headers for the different Ruby VM versions;
  # see https://github.com/DataDog/datadog-ruby_core_source for details

  create_header

  require "datadog/ruby_core_source"
  dir_config("ruby") # allow user to pass in non-standard core include directory

  # This is a workaround for a weird issue...
  #
  # The mkmf tool defines a `with_cppflags` helper that datadog-ruby_core_source uses. This helper temporarily
  # replaces `$CPPFLAGS` (aka the C pre-processor [not c++!] flags) with a different set when doing something.
  #
  # The datadog-ruby_core_source gem uses `with_cppflags` during makefile generation to inject extra headers into the
  # path. But because `with_cppflags` replaces `$CPPFLAGS`, well, the default `$CPPFLAGS` are not included in the
  # makefile.
  #
  # This is a problem because the default `$CPPFLAGS` carries configuration that was set when Ruby was being built.
  # Thus, if we ignore it, we don't compile the profiler with the exact same configuration as Ruby.
  # In practice, this can generate crashes and weird bugs if the Ruby configuration is tweaked in a manner that
  # changes some of the internal structures that the profiler relies on. Concretely, setting for instance
  # `VM_CHECK_MODE=1` when building Ruby will trigger this issue (because somethings in structures the profiler reads
  # are ifdef'd out using this setting).
  #
  # To workaround this issue, we override `with_cppflags` for datadog-ruby_core_source to still include `$CPPFLAGS`.
  Datadog::RubyCoreSource.define_singleton_method(:with_cppflags) do |newflags, &block|
    super("#{newflags} #{$CPPFLAGS}", &block)
  end

  Datadog::RubyCoreSource
    .create_makefile_with_core(
      proc do
        headers_available =
          have_header("vm_core.h") &&
          have_header("iseq.h") &&
          (RUBY_VERSION < "3.3" || have_header("ractor_core.h"))

        if headers_available
          # Warn on unused parameters to functions. Use `DDTRACE_UNUSED` to mark things as known-to-not-be-used.
          # This is added as late as possible because in some Rubies we support (e.g. 3.3), adding this flag before
          # checking if internal VM headers are available causes those checks to fail because of this warning (and not
          # because the headers are not available.)
          append_cflags "-Wunused-parameter"
        end

        headers_available
      end,
      EXTENSION_NAME
    )
end

# rubocop:enable Style/GlobalVars
# rubocop:enable Style/StderrPuts
