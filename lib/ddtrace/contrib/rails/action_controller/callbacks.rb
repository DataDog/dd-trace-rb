require 'ddtrace/contrib/rails/active_support/callbacks'
require 'ddtrace/contrib/rails/action_controller/callbacks/rails50'

module Datadog
  module Contrib
    module Rails
      module ActionController
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            if ::Rails.version >= '5.1'
              base.include(ActiveSupport::Callbacks)
            elsif ::Rails.version >= '5.0'
              base.include(Rails50)
            end
          end
        end
      end
    end
  end
end
