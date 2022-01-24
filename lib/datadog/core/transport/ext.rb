# typed: true
module Datadog
  module Core
    # @public_api
    module Transport
      module Ext
        # @public_api
        module HTTP
          ADAPTER = :net_http # DEV: Rename to simply `:http`, as Net::HTTP is an implementation detail.
          DEFAULT_HOST = '127.0.0.1'.freeze
          DEFAULT_PORT = 8126
          DEFAULT_TIMEOUT_SECONDS = 1
          ENV_DEFAULT_HOST = 'DD_AGENT_HOST'.freeze
          HEADER_CONTAINER_ID = 'Datadog-Container-ID'.freeze
          HEADER_DD_API_KEY = 'DD-API-KEY'.freeze
          HEADER_META_LANG = 'Datadog-Meta-Lang'.freeze
          HEADER_META_LANG_VERSION = 'Datadog-Meta-Lang-Version'.freeze
          HEADER_META_LANG_INTERPRETER = 'Datadog-Meta-Lang-Interpreter'.freeze
        end

        # @public_api
        module Test
          ADAPTER = :test
        end

        # @public_api
        module UnixSocket
          ADAPTER = :unix
          DEFAULT_PATH = '/var/run/datadog/apm.socket'.freeze
          DEFAULT_TIMEOUT_SECONDS = 1
        end
      end
    end
  end
end
