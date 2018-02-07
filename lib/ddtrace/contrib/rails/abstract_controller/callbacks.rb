require 'ddtrace/contrib/rails/abstract_controller/callbacks/action_tracing'

module Datadog
  module Contrib
    module Rails
      module AbstractController
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            begin
              # Support only Rails 5.0.x and 5.1.x
              if ::Rails.version >= '5.0' && ::Rails.version < '5.2'
                base.prepend(ActionTracing)
              end
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to patch AbstractController callbacks: #{e}")
            end
          end
        end
      end
    end
  end
end
