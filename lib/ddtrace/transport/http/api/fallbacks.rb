module Datadog
  module Transport
    module HTTP
      module API
        # Extension for Map with adds fallback versions.
        module Fallbacks
          def fallbacks
            @fallbacks ||= {}
          end

          def fallback_for(key)
            self[fallbacks[key]]
          end

          def with_fallbacks(fallbacks)
            tap { add_fallbacks!(fallbacks) }
          end

          def add_fallbacks!(fallbacks)
            self.fallbacks.merge!(fallbacks)
          end
        end
      end
    end
  end
end
