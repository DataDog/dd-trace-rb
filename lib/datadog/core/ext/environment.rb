require 'ddtrace/version'

module Datadog
  module Core
    module Ext
      module Environment
        # Identity
        LANG = 'ruby'.freeze
        LANG_ENGINE = RUBY_ENGINE
        LANG_INTERPRETER = "#{RUBY_ENGINE}-#{RUBY_PLATFORM}".freeze
        LANG_PLATFORM = RUBY_PLATFORM
        LANG_VERSION = RUBY_VERSION
        RUBY_ENGINE = ::RUBY_ENGINE # e.g. 'ruby', 'jruby', 'truffleruby'
        TRACER_VERSION = Datadog::VERSION::STRING

        FALLBACK_SERVICE_NAME =
          begin
            File.basename($PROGRAM_NAME, '.*')
          rescue StandardError
            'ruby'
          end.freeze
      end
    end
  end
end
