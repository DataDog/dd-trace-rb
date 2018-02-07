require 'ddtrace/contrib/rails/active_support/callbacks'
require 'ddtrace/contrib/rails/action_controller/callbacks/rails50'

module Datadog
  module Contrib
    module Rails
      module ActionController
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            # 5.1.x only
            if ::Rails.version >= '5.1' && ::Rails.version < '5.2'
              base.include(ActiveSupport::Callbacks)
            # 5.0.x only
            elsif ::Rails.version >= '5.0' && ::Rails.version < '5.1'
              base.include(Rails50)
            end
          rescue StandardError => e
            Datadog::Tracer.log.error("Unable to patch ActionController callbacks: #{e}")
          end
        end
      end
    end
  end
end
