module Datadog
  module Contrib
    module Configuration
      # Represents a definition for an integration configuration
      class IntegrationDefinition
        attr_reader \
          :default_configuration_name,
          :name

        def initialize(name, meta = {})
          @name = name.to_sym
          @enabled = meta.fetch(:enabled, true)
          @defer = meta.fetch(:defer, false)
          @default_configuration_name = meta.fetch(:default_configuration_name, :default)
        end

        def defer?
          @defer == true
        end

        def enabled?
          @enabled == true
        end
      end
    end
  end
end
