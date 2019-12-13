module Datadog
  module Contrib
    module Configuration
      # Resolves a value to a configuration key
      class Resolver
        def add_key(key)
          # noop here, override in your subclass to customize
        end

        def resolve(name)
          name
        end
      end
    end
  end
end
