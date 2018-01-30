require 'ddtrace/contrib/rails/active_support/callbacks/rails51'

module Datadog
  module Contrib
    module Rails
      module ActiveSupport
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            base.include(Rails51)
          end
        end
      end
    end
  end
end
