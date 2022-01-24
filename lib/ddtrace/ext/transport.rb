# typed: true
module Datadog
  module Ext
    # @public_api
    module Transport
      # @public_api
      module HTTP
        ENV_DEFAULT_PORT = 'DD_TRACE_AGENT_PORT'.freeze
        ENV_DEFAULT_URL = 'DD_TRACE_AGENT_URL'.freeze
        HEADER_META_TRACER_VERSION = 'Datadog-Meta-Tracer-Version'.freeze
      end
    end
  end
end
