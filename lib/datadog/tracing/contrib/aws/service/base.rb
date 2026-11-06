# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Base class for all AWS service-specific tag handlers.
          class Base
            def add_tags(span, params)
            end

            private

            # Sets a target-identity name tag, skipping a nil or empty name so
            # an unresolved target is never reported as a named one.
            def set_resolved_name(span, key, name)
              return if name.nil? || name == ""

              span.set_tag(key, name)
            end
          end
        end
      end
    end
  end
end
