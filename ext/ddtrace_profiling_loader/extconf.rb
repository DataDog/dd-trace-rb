# typed: ignore

# rubocop:disable Style/StderrPuts
# rubocop:disable Style/GlobalVars

if RUBY_ENGINE != 'ruby' || Gem.win_platform?
  $stderr.puts(
    'WARN: Skipping build of ddtrace profiling loader. See ddtrace profiling native extension note for details.'
  )

  File.write('Makefile', 'all install clean: # dummy makefile that does nothing')
  exit
end

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

# Gets really noisy when we include the MJIT header, let's omit it
add_compiler_flag '-Wno-unused-function'

# Allow defining variables at any point in a function
add_compiler_flag '-Wno-declaration-after-statement'

# If we forget to include a Ruby header, the function call may still appear to work, but then
# cause a segfault later. Let's ensure that never happens.
add_compiler_flag '-Werror-implicit-function-declaration'

# The native extension is not intended to expose any symbols/functions for other native libraries to use;
# the sole exception being `Init_ddtrace_profiling_loader` which needs to be visible for Ruby to call it when
# it `dlopen`s the library.
#
# By setting this compiler flag, we tell it to assume that everything is private unless explicitly stated.
# For more details see https://gcc.gnu.org/wiki/Visibility
add_compiler_flag '-fvisibility=hidden'

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "ddtrace_profiling_loader.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

create_makefile(EXTENSION_NAME)

# rubocop:enable Style/GlobalVars
# rubocop:enable Style/StderrPuts
