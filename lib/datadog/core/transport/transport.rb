# frozen_string_literal: true

require_relative 'http/client'

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

      # Raised when the API verson to downgrade to does not map to a
      # defined API.
      class NoDowngradeAvailableError < StandardError
        attr_reader :version

        def initialize(version)
          super

          @version = version
        end

        def message
          "No downgrade from transport API version #{version} is available!"
        end
      end

      # Base class for transports.
      class Transport
        attr_reader :client, :apis, :default_api, :current_api_id, :logger

        class << self
          # The HTTP client class to use for requests, derived from
          # Core::Transport::HTTP::Client.
          #
          # Important: this attribute is NOT inherited by derived classes -
          # it must be set by every Transport class that wants to have a
          # non-default HTTP::Client instance.
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
          client_class = self.class.http_client_class || Core::Transport::HTTP::Client
          @client = client_class.new(current_api, logger: logger) # steep:ignore
        end

        def downgrade?(response)
          return false unless apis.fallbacks.key?(current_api_id)

          response.not_found? || response.unsupported?
        end

        def downgrade!
          downgrade_api_id = apis.fallbacks[current_api_id]
          raise NoDowngradeAvailableError, current_api_id if downgrade_api_id.nil?

          set_api!(downgrade_api_id)
        end
      end
    end
  end
end
