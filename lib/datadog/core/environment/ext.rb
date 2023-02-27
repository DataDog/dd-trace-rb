require_relative '../../../ddtrace/version'

module Datadog
  module Core
    module Environment
      # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
      module Ext
        # e.g for CRuby '3.0.1', for JRuby '9.2.19.0', for TruffleRuby '21.1.0'
        ENGINE_VERSION = if defined?(RUBY_ENGINE_VERSION)
                           RUBY_ENGINE_VERSION
                         else
                           # CRuby < 2.3 doesn't support RUBY_ENGINE_VERSION
                           RUBY_VERSION
                         end

        ENV_API_KEY = 'DD_API_KEY'.freeze
        ENV_ENVIRONMENT = 'DD_ENV'.freeze
        ENV_SERVICE = 'DD_SERVICE'.freeze
        ENV_SITE = 'DD_SITE'.freeze
        ENV_TAGS = 'DD_TAGS'.freeze
        ENV_VERSION = 'DD_VERSION'.freeze
        FALLBACK_SERVICE_NAME =
          begin
            File.basename($PROGRAM_NAME, '.*')
          rescue StandardError
            'ruby'
          end.freeze

        LANG = 'ruby'.freeze
        LANG_ENGINE = RUBY_ENGINE
        LANG_INTERPRETER = "#{RUBY_ENGINE}-#{RUBY_PLATFORM}".freeze
        LANG_PLATFORM = RUBY_PLATFORM
        LANG_VERSION = RUBY_VERSION
        RUBY_ENGINE = ::RUBY_ENGINE # e.g. 'ruby', 'jruby', 'truffleruby'
        TAG_ENV = 'env'.freeze
        TAG_SERVICE = 'service'.freeze
        TAG_VERSION = 'version'.freeze

        # TODO: Migrate to Datadog::Tracing
        TRACER_VERSION = DDTrace::VERSION::STRING
      end
    end
  end
end
