# frozen_string_literal: true

require_relative '../analytics'

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        # common utilities for ViewComponent
        module Utils
          module_function

          # in ViewComponent the component identifier includes the component full path
          # and it's better to avoid storing such information. This method
          # returns the relative path from `components/` or the component identifier
          # if a `components/` folder is not in the component full path. A wrong
          # usage ensures that this method will not crash the tracing system.
          def normalize_component_identifier(identifier)
            return if identifier.nil?

            base_path = Datadog.configuration.tracing[:view_component][:component_base_path]
            sections_view = identifier.split(base_path)

            if sections_view.length == 1
              identifier.split('/')[-1]
            else
              sections_view[-1]
            end
          rescue
            identifier.to_s
          end
        end
      end
    end
  end
end
