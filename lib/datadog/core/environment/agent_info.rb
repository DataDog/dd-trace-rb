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

        def initialize(agent_settings, logger: Datadog.logger)
          @agent_settings = agent_settings
          @logger = logger
          @client = Remote::Transport::HTTP.root(agent_settings: agent_settings, logger: logger)
        end

        # Fetches the information from the Trace Agent.
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

        # Returns the propagation hash from the Agent.
        # Currently called/used by the DBM code to inject the propagation hash into the SQL comment
        # @return [Integer, nil] the FNV hash based on the container and process tags or nil
        def propagation_hash
          # Can't use defined?(@propagation_hash) here because it will return true if @propagation_hash is nil
          return @propagation_hash if @propagation_hash
          fetch if @container_tags_checksum.nil?
          return unless @container_tags_checksum

          process_tags = Process.serialized
          data = process_tags + container_tags_checksum
          @propagation_hash = Core::Utils::FNV.fnv1_64(data)
        end

        private

        # Trace Agent 7.69.0+ provides a SHA256 checksum in the response header DATADOG-CONTAINER-TAGS-HASH based on the container id computed in Datadog::Core::Environment::Container
        # During calls to the Trace Agent, this checksum is cached but invalidated if a new value is returned
        # The resulting propagation_hash uses the container_tags_checksum
        # https://github.com/DataDog/datadog-agent/pull/38515
        attr_reader :container_tags_checksum

        # Datadog::Core::Environment::Container extracts the container id if possible and sends them to the Trace Agent via the header Datadog-Container-ID
        # The Trace Agent takes the container id and looks for matching container tags to compute a SHA256 checksum via the response header DATADOG-CONTAINER-TAGS-HASH
        # https://github.com/DataDog/datadog-agent/blob/c923da011c8e51c35c0d05b6b10d016521915e7d/pkg/trace/api/info.go#L203-L227
        # When deciding whether the propagation checksum should be updated, we need to be aware of some concerns
        #     - It is possible that older Trace Agents may not have this specific header
        #     - It is possible that we don't have access to the value if the Trace Agent is temporarily down. In these cases, we need to check for the value again on the next call to the info endpoint
        #     - If we have access to the value, we need to check if it changed from the previous value.
        def update_container_tags(res)
          header_value = res.headers[Core::Transport::Ext::HTTP::HEADER_CONTAINER_TAGS_HASH]
          new_container_tags_value = header_value if header_value && !header_value.empty?

          # if the Trace Agent returns a new value for the checksum, invalidate the cached propagation hash
          if new_container_tags_value && new_container_tags_value != @container_tags_checksum
            @container_tags_checksum = new_container_tags_value
            @propagation_hash = nil
          end
        end
      end
    end
  end
end
