module Datadog
  module Contrib
    module Configuration
      # Resolves a configuration key to a Datadog::Contrib::Configuration:Settings object
      class Resolver
        def resolve(key)
          key
        end

        def add(key)
          key
        end
      end
    end
  end
end
