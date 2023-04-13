module Datadog
  module Core
    module Metrics
      # @public_api
      module Ext
        DEFAULT_HOST = '127.0.0.1'.freeze
        DEFAULT_PORT = 8125

        TAG_LANG = 'language'.freeze
        TAG_LANG_INTERPRETER = 'language-interpreter'.freeze
        TAG_LANG_VERSION = 'language-version'.freeze
        TAG_TRACER_VERSION = 'tracer-version'.freeze
      end
    end
  end
end
