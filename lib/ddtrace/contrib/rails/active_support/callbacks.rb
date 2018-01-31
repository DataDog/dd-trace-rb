require 'ddtrace/contrib/rails/active_support/callbacks/rails50'
require 'ddtrace/contrib/rails/active_support/callbacks/rails51'

module Datadog
  module Contrib
    module Rails
      module ActiveSupport
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            if ::Rails.version >= '5.1'
              base.include(Rails51)
            elsif ::Rails.version >= '5.0'
              base.include(Rails50)
            end
          end
        end
      end
    end
  end
end
