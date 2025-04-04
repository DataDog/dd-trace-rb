# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Faraday
        # Handles installation of our middleware if the user has *not*
        # already explicitly configured our middleware for this correction.
        #
        # Wraps Faraday::Connection#initialize:
        # https://github.com/lostisland/faraday/blob/ff9dc1d1219a1bbdba95a9a4cf5d135b97247ee2/lib/faraday/connection.rb#L62-L92
        module ConnectionPatch
          def initialize(*args, &block)
            super.tap do
              use(:datadog_appsec) unless builder.handlers.any? { |h| h.klass == SSRFDetectionMiddleware }
            end
          end
        end
      end
    end
  end
end
