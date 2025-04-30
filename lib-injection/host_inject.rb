# This file's intent is to be parseable and executable by all ruby versions
# to call into the main one only for versions for which it is known-compatible
# with at the language level.

if RUBY_VERSION >= '2.3.'
  require File.expand_path(File.join(File.dirname(__FILE__), 'host_inject_main.rb'))
end
