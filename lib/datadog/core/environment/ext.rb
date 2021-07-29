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

        # e.g for CRuby '3.0.1', for JRuby '9.2.19.0', for TruffleRuby '21.1.0'
        ENGINE_VERSION = if defined?(RUBY_ENGINE_VERSION)
                           RUBY_ENGINE_VERSION
                         else
                           # CRuby < 2.3 doesn't support RUBY_ENGINE_VERSION
                           RUBY_VERSION
                         end
      end
    end
  end
end
