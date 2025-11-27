# frozen_string_literal: true

module Datadog
  module Core
    module Transport
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

      module HTTP
        module API
          # Functionality for downgrading API to a fallback one.
          module Downgradable
            private

            def downgrade?(response)
              return false unless apis.fallbacks.key?(@current_api_id)

              response.not_found? || response.unsupported?
            end

            def downgrade!
              downgrade_api_id = apis.fallbacks[@current_api_id]
              raise NoDowngradeAvailableError, @current_api_id if downgrade_api_id.nil?

              set_api!(downgrade_api_id)
            end
          end
        end
      end
    end
  end
end
