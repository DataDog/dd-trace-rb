module Datadog
  module Contrib
    module Configuration
      # Represents a definition for an integration configuration
      class IntegrationDefinition
        attr_reader \
          :name,
          :default

        def initialize(name, meta = {}, &block)
          @name = name.to_sym
          @enabled = meta.fetch(:enabled, true)
          @defer = meta.fetch(:defer, false)
          @default = block if block_given?
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
