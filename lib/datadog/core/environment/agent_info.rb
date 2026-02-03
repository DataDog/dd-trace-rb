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

          update_propagation_checksum(res)

          res
        end

        def ==(other)
          other.is_a?(self.class) && other.agent_settings == agent_settings
        end

        # Returns the propagation checksum, comprising of process tags and optionally container tags (from the Trace Agent)
        # Currently called/used by the DBM code to inject the propagation checksum into the SQL comment.
        #
        # This checksum is used for correlation across signals (traces, DBM, data streams, etc.) in environments
        #
        # The checksum is populated by the trace transport's periodic fetch calls.
        # @return [Integer, nil] the FNV hash based on the container and process tags or nil
        attr_reader :propagation_checksum

        private

        # Trace Agent 7.69.0+ provides a SHA256 checksum in the response header DATADOG-CONTAINER-TAGS-HASH based on the container id computed in Datadog::Core::Environment::Container
        # This is a short checksum that uniquely identifies this process, its container environment, and
        # the Datadog agent it connects to.
        #
        # This checksum only has to be internally consistent: the same value must be used by every signal
        # emitted by this process+container+agent combinations). It is not required that this checksum is
        # consistent with other SDKs.
        # During calls to the Trace Agent, this checksum is cached but invalidated if a new value is returned
        # The resulting propagation_checksum uses the container_tags_checksum
        # https://github.com/DataDog/datadog-agent/pull/38515
        attr_reader :container_tags_checksum

        # Computes the propagation checksum from process tags and optionally container tags when it changes
        # Controlled by DD_EXPERIMENTAL_PROPAGATE_PROCESS_TAGS_ENABLED
        # This is needed in traces (dsm and dbm related spans), DBM, and DSM.
        #
        # Only runs when  is true.
        #
        # Container tags extraction:
        # Datadog::Core::Environment::Container extracts the container id from the cgroup folder if possible
        # (note: not currently available in cgroupv2) and sends it to the Trace Agent via the header Datadog-Container-ID.
        # The Trace Agent takes the container id and looks for matching container tags to compute a SHA256 checksum via the response header DATADOG-CONTAINER-TAGS-HASH
        # https://github.com/DataDog/datadog-agent/blob/c923da011c8e51c35c0d05b6b10d016521915e7d/pkg/trace/api/info.go#L203-L227
        #
        # When deciding whether the propagation checksum should be updated, we need to be aware of some concerns:
        #     - The tracer fails to send the container id in the first place
        #     - It is possible that older Trace Agents may not have this specific header
        #     - It is possible that we don't have access to the value if the Trace Agent is temporarily down. In these cases, we need to check for the value again on the next call to the info endpoint
        #     - If we have access to the value, we need to check if it changed from the previous value.
        #     - The Trace Agent runs into a permissions/setup issue.
        def update_propagation_checksum(res)
          return unless Datadog.configuration.experimental_propagate_process_tags_enabled

          header_value = res.headers[Core::Transport::Ext::HTTP::HEADER_CONTAINER_TAGS_HASH]
          new_container_tags_value = header_value if header_value && !header_value.empty?

          # if the Trace Agent returns a new value for the checksum, calculate and cache the propagation checksum
          # If there was no previous propagation_checksum, then we should calculate the checksum by checking the agent and getting process info
          if @propagation_checksum.nil? || (new_container_tags_value && new_container_tags_value != @container_tags_checksum)
            @container_tags_checksum = new_container_tags_value

            data = Process.serialized
            # Add container tags if available (helps Steep with type narrowing)
            container_tags = @container_tags_checksum
            data += container_tags if container_tags

            @propagation_checksum = Core::Utils::FNV.fnv1_64(data)
          end
        end
      end
    end
  end
end
