require 'mkmf'

create_header

$CFLAGS << ' -Wall -Wextra -std=c99'

# Add include paths for Datadog profiling library
$CFLAGS << ' -I/opt/homebrew/include'  # For Homebrew-installed libraries
$CFLAGS << ' -I/usr/local/include'     # For system-wide installations

EXTENSION_NAME = "errortracker.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}".freeze
create_makefile('errortracker')
