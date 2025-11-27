# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      # Raised when configured with an unknown API version
      class UnknownApiVersionError < StandardError
        attr_reader :version

        def initialize(version)
          super

          @version = version
        end

        def message
          "No matching transport API for version #{version}!"
        end
      end

      class HTTPClientClassNotSet < StandardError
      end

      # Base class for transports.
      class Transport
        attr_reader :client, :apis, :default_api, :current_api_id, :logger

        class << self
          # The HTTP client class to use for requests, derived from
          # Core::Transport::HTTP::Client.
          #
          # Important: this attribute is NOT inherited by derived classes -
          # it must be set by/for every Transport class.
          attr_accessor :http_client_class
        end

        def initialize(apis, default_api, logger:)
          @apis = apis
          @default_api = default_api
          @logger = logger

          set_api!(default_api)
        end

        def current_api
          apis[current_api_id]
        end

        private

        def set_api!(api_id)
          raise UnknownApiVersionError, api_id unless apis.key?(api_id)

          @current_api_id = api_id
          unless (client_class = self.class.http_client_class)
            raise HTTPClientClassNotSet, "http_client_class is not set for #{self.class}"
          end
          @client = client_class.new(current_api, logger: logger)
        end
      end
    end
  end
end
