require 'ddtrace/contrib/rails/abstract_controller/callbacks/action_tracing'

module Datadog
  module Contrib
    module Rails
      module AbstractController
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            base.prepend(ActionTracing) if ::Rails.version >= '5.0'
          end
        end
      end
    end
  end
end
