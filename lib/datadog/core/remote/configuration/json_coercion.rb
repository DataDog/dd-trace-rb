# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      class Configuration
        # Coercions from parsed remote-configuration JSON values to Ruby types.
        module JSONCoercion
          module_function

          # Coerces +value+ to an Integer when it is an Integer or a base-10
          # integer String, returning nil otherwise.
          def coerce_integer(value)
            case value
            when Integer
              value
            when String
              value.match?(/\A-?\d+\z/) ? value.to_i : nil
            end
          end
        end
      end
    end
  end
end
