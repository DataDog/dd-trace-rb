if RUBY_ENGINE != 'ruby' || Gem.win_platform?
  $stderr.puts(
    'WARN: Skipping build of libdatadog_api. Some functionality will not be available.'
  )

  File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  exit
end

require 'mkmf'

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

if ENV['DDTRACE_DEBUG']
  $defs << '-DDD_DEBUG'
  CONFIG['optflags'] = '-O0'
  CONFIG['debugflags'] = '-ggdb3'
end

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "libdatadog_api.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

create_makefile(EXTENSION_NAME)
