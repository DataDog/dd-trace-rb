# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      module Event
        module ConfigurationValue
          module_function

          def convert(value)
            case value
            when Integer, String, true, false, nil
              value
            when Float
              value.finite? ? value : value.to_s
            when Hash
              value.map { |key, entry_value| "#{key}:#{entry_value}" }.join(",")
            when Array
              value.join(",")
            when Module
              value.name.to_s
            else
              implements_to_s = begin
                value.method(:to_s).owner != Kernel
              rescue NameError
                false
              end

              if implements_to_s
                value.to_s
              else
                value.class.to_s
              end
            end
          end
        end
      end
    end
  end
end
