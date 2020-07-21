module Datadog
  module Ext
    module Transport
      module HTTP
        DEFAULT_HOST = '127.0.0.1'.freeze
        DEFAULT_PORT = 8126
        ENV_DEFAULT_HOST = 'DD_AGENT_HOST'.freeze
        ENV_DEFAULT_PORT = 'DD_TRACE_AGENT_PORT'.freeze
        ENV_DEFAULT_URL = 'DD_TRACE_AGENT_URL'.freeze
        HEADER_CONTAINER_ID = 'Datadog-Container-ID'.freeze
        HEADER_DD_API_KEY = 'DD-API-KEY'.freeze
        HEADER_META_LANG = 'Datadog-Meta-Lang'.freeze
        HEADER_META_LANG_VERSION = 'Datadog-Meta-Lang-Version'.freeze
        HEADER_META_LANG_INTERPRETER = 'Datadog-Meta-Lang-Interpreter'.freeze
        HEADER_META_TRACER_VERSION = 'Datadog-Meta-Tracer-Version'.freeze
      end
    end
  end
end
