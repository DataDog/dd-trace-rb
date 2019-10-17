module Datadog
  module Transport
    module HTTP
      # Sends traces based on transport API configuration.
      #
      # This class initializes the HTTP client, breaks down large
      # batches of traces into smaller chunks and handles
      # API version downgrade handshake.
      class Transport
        attr_reader :client, :apis, :default_api, :current_api_id

        def initialize(apis, default_api)
          @apis = apis
          @default_api = default_api

          change_api!(default_api)
        end

        def send_traces(traces)
          encoder = current_api.encoder
          encoder.encode_traces(traces) do |encoded_traces, trace_count|
            request = Datadog::Transport::Traces::Request.new(
              encoded_traces,
              trace_count,
              encoder.content_type
            )

            client.send_payload(request).tap do |response|
              if downgrade?(response)
                downgrade!
                return send_traces(traces)
              end
            end
          end
        end

        def stats
          @client.stats
        end

        def current_api
          apis[@current_api_id]
        end

        private

        def downgrade?(response)
          return false unless apis.fallbacks.key?(@current_api_id)
          response.not_found? || response.unsupported?
        end

        def downgrade!
          downgrade_api_id = apis.fallbacks[@current_api_id]
          raise NoDowngradeAvailableError, @current_api_id if downgrade_api_id.nil?
          change_api!(downgrade_api_id)
        end

        def change_api!(api_id)
          raise UnknownApiVersionError, api_id unless apis.key?(api_id)
          @current_api_id = api_id
          @client = Client.new(current_api)
        end

        # Raised when configured with an unknown API version
        class UnknownApiVersionError < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No matching transport API for version #{version}!"
          end
        end

        # Raised when configured with an unknown API version
        class NoDowngradeAvailableError < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No downgrade from transport API version #{version} is available!"
          end
        end
      end
    end
  end
end
