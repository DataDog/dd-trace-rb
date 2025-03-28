# rubocop:disable Style/StderrPuts
# rubocop:disable Style/GlobalVars

require 'rubygems'
require 'mkmf'

def skip_building_extension!(reason)
  $stderr.puts(
    "WARN: Skipping build of errortracker (#{reason}). Some functionality will not be available."
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

# Because we can't control what compiler versions our customers use, shipping with -Werror by default is a no-go.
# But we can enable it in CI, so that we quickly spot any new warnings that just got introduced.
append_cflags '-Werror' if ENV['DATADOG_GEM_CI'] == 'true'

# Older gcc releases may not default to C99 and we need to ask for this. This is also used:
# * by upstream Ruby -- search for gnu99 in the codebase
# * by msgpack, another datadog gem dependency
#   (https://github.com/msgpack/msgpack-ruby/blob/18ce08f6d612fe973843c366ac9a0b74c4e50599/ext/msgpack/extconf.rb#L8)
append_cflags '-std=gnu99'

# Allow defining variables at any point in a function
append_cflags '-Wno-declaration-after-statement'

# If we forget to include a Ruby header, the function call may still appear to work, but then
# cause a segfault later. Let's ensure that never happens.
append_cflags '-Werror-implicit-function-declaration'

# Warn on unused parameters to functions. Use `DDTRACE_UNUSED` to mark things as known-to-not-be-used.
append_cflags '-Wunused-parameter'

# The native extension is not intended to expose any symbols/functions for other native libraries to use;
# the sole exception being `Init_errortracker` which needs to be visible for Ruby to call it when
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

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "errortracker.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}".freeze

create_makefile(EXTENSION_NAME)

# rubocop:enable Style/GlobalVars
# rubocop:enable Style/StderrPuts
