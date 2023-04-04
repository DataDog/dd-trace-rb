module Datadog
  module Tracing
    module Contrib
      module Rails
        module Test
          module Configuration
            module_function

            def original
              @original ||= {}
            end

            def fetch(key, value)
              return get(key) if original.key?(key)

              value.tap { set(key, value) }
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
end
