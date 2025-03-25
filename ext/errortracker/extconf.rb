require 'mkmf'

$CFLAGS << ' -Wall -Wextra -std=c99'

EXTENSION_NAME = "errortracker.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}".freeze
create_makefile(EXTENSION_NAME)
