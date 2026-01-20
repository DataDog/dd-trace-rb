# frozen_string_literal: true

require_relative '../utils/fnv'
require_relative 'process'

module Datadog
  module Core
    module Environment
      # Retrieves the agent's `/info` endpoint data.
      # This data can be used to determine the capabilities of the local Datadog agent.
      #
      # @example Example response payload
      #   {
      #     "version" : "7.57.2",
      #     "git_commit" : "38ba0c7",
      #     "endpoints" : [ "/v0.4/traces", "/v0.4/services", "/v0.7/traces", "/v0.7/config" ],
      #     "client_drop_p0s" : true,
      #     "span_meta_structs" : true,
      #     "long_running_spans" : true,
      #     "evp_proxy_allowed_headers" : [ "Content-Type", "Accept-Encoding", "Content-Encoding", "User-Agent" ],
      #     "config" : {
      #       "default_env" : "none",
      #       "target_tps" : 10,
      #       "max_eps" : 200,
      #       "receiver_port" : 8126,
      #       "receiver_socket" : "/var/run/datadog/apm.socket",
      #       "connection_limit" : 0,
      #       "receiver_timeout" : 0,
      #       "max_request_bytes" : 26214400,
      #       "statsd_port" : 8125,
      #       "analyzed_spans_by_service" : { },
      #       "obfuscation" : {
      #         "elastic_search" : true,
      #         "mongo" : true,
      #         "sql_exec_plan" : false,
      #         "sql_exec_plan_normalize" : false,
      #         "http" : {
      #           "remove_query_string" : false,
      #           "remove_path_digits" : false
      #         },
      #         "remove_stack_traces" : false,
      #         "redis" : {
      #           "Enabled" : true,
      #           "RemoveAllArgs" : false
      #         },
      #         "memcached" : {
      #           "Enabled" : true,
      #           "KeepCommand" : false
      #         }
      #       }
      #     },
      #     "peer_tags" : null
      #   }
      #
      # @see https://github.com/DataDog/datadog-agent/blob/f07df0a3c1fca0c83b5a15f553bd994091b0c8ac/pkg/trace/api/info.go#L20
      class AgentInfo
        attr_reader :agent_settings, :logger
        # Container tags originally set to nil, but gets populated from #fetch when available
        attr_reader :container_tags_checksum

        def initialize(agent_settings, logger: Datadog.logger)
          @agent_settings = agent_settings
          @logger = logger
          @client = Remote::Transport::HTTP.root(agent_settings: agent_settings, logger: logger)
        end

        # Fetches the information from the agent.
        # Extracts container tags from response headers
        # @return [Datadog::Core::Remote::Transport::HTTP::Negotiation::Response] the response from the agent
        # @return [nil] if an error occurred while fetching the information
        def fetch
          res = @client.send_info
          return unless res.ok?

          update_container_tags(res)

          res
        end

        def ==(other)
          other.is_a?(self.class) && other.agent_settings == agent_settings
        end

        # Returns the propagation hash from the Agent if not previously cached
        # @return [Integer, nil] the FNV hash based on the container and process tags or nil
        def propagation_hash
          return @propagation_hash if @propagation_hash
          fetch if @container_tags_checksum.nil?
          container_tags_checksum = @container_tags_checksum
          return nil unless container_tags_checksum

          process_tags = Process.serialized
          data = process_tags + container_tags_checksum
          @propagation_hash = Core::Utils::FNV.fnv1_64(data)
        end

        private

        def update_container_tags(res)
          return unless res.respond_to?(:headers)

          header_value = res.headers[Core::Transport::Ext::HTTP::HEADER_CONTAINER_TAGS_HASH]
          new_container_tags_value = header_value if header_value && !header_value.empty?

          # if there are new container tags from the agent,
          # set the hash to nil so it gets recomputed the next time the hash string is created
          if new_container_tags_value && new_container_tags_value != @container_tags_checksum
            @container_tags_checksum = new_container_tags_value
            @propagation_hash = nil
          end
        end
      end
    end
  end
end
