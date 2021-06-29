require 'ddtrace/version'

module Datadog
  module Core
    module Environment
      module Ext
        # Identity
        LANG = 'ruby'.freeze
        LANG_ENGINE = RUBY_ENGINE
        LANG_INTERPRETER = "#{RUBY_ENGINE}-#{RUBY_PLATFORM}".freeze
        LANG_PLATFORM = RUBY_PLATFORM
        LANG_VERSION = RUBY_VERSION
        RUBY_ENGINE = ::RUBY_ENGINE # e.g. 'ruby', 'jruby', 'truffleruby'
        TRACER_VERSION = Datadog::VERSION::STRING
      end
    end
  end
end
