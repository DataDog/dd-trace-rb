module Datadog
  module Security
    module Configuration
      # Configuration settings, acting as an integration registry
      # TODO: as with Configuration, this is a trivial implementation
      class Settings
        def initialize
          @integrations = []
        end

        def merge(dsl)
          dsl.uses.each do |use|
            name, _options = use
            registered_integration = Datadog::Security::Contrib::Integration.registry[name]
            @integrations << registered_integration

            klass = registered_integration.klass
            if klass.loaded? && klass.compatible?
              instance = klass.new
              instance.patcher.patch
            end
          end

          self
        end
      end
    end
  end
end
