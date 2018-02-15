module Datadog
  module Contrib
    module Rails
      module Test
        module Configuration
          module_function

          def original
            @original ||= {}
          end

          def set(key, value)
            original[key] = value
          end

          def get(key)
            original[key]
          end
        end
      end
    end
  end
end
