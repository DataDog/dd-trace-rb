module Datadog
  module Transport
    module HTTP
      # Extension for APIMap with adds fallback versions.
      module Fallbacks
        def fallbacks
          @fallbacks ||= {}
        end

        def fallback_from(key)
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
