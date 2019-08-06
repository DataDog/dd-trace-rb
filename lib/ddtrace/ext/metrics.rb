module Datadog
  module Ext
    module Metrics
      DEFAULT_HOST = '127.0.0.1'.freeze
      DEFAULT_PORT = 8125
      ENV_DEFAULT_HOST = 'DD_AGENT_HOST'.freeze
      ENV_DEFAULT_PORT = 'DD_METRIC_AGENT_PORT'.freeze

      TAG_LANG = 'language'.freeze
      TAG_LANG_INTERPRETER = 'language-interpreter'.freeze
      TAG_LANG_VERSION = 'language-version'.freeze
      TAG_TRACER_VERSION = 'tracer-version'.freeze
    end
  end
end
