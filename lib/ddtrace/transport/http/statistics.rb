require 'ddtrace/transport/statistics'

module Datadog
  module Transport
    module HTTP
      # Tracks statistics for HTTP transports
      module Statistics
        def self.included(base)
          base.send(:include, Transport::Statistics)
          base.send(:include, InstanceMethods)
        end

        # Instance methods for HTTP statistics
        module InstanceMethods
          # Decorate metrics for HTTP responses
          def metrics_for_response(response)
            super.tap do |metrics|
              # Add status code tag to api.responses metric
              if metrics.key?(:api_responses)
                (metrics[:api_responses].options[:tags] ||= []).tap do |tags|
                  tags << "status_code:#{response.code}"
                end
              end
            end
          end
        end
      end
    end
  end
end
