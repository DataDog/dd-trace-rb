module Datadog
  module Contrib
    module Configuration
      # Represents an instance of a configurable integration
      class Integration
        attr_reader \
          :definition,
          :callbacks

        def initialize(definition)
          @definition = definition
          reset
        end

        def enable!
          @enabled = true
        end

        def disable!
          @enabled = false
        end

        def enabled?
          @enabled == true
        end

        def configure(*args, &block)
          if args.first == false
            disable!
          elsif args.first == true
            enable!
          elsif args.any? || block_given?
            add_configuration_callback(*args, &block)
          end
        end

        # Add a configuration callback
        def add_configuration_callback(*args, &block)
          # Defer execution by wrapping in a proc
          callback = proc do
            Datadog.configuration.set(
              definition.name,
              *args,
              &block
            )
          end

          # Add callback to collection
          callbacks << callback
        end

        # Apply configuration and activate the integration
        def activate!(*args, &block)
          return unless enabled?

          # Apply default settings to block first
          if block_given?
            Datadog.configuration.set(
              definition.name,
              *args,
              &block
            )
          end

          # Then apply all configuration callbacks
          callbacks.each(&:call)

          # Then activate the integration
          Datadog.configuration.use(definition.name)
        end

        def reset
          @enabled = definition.enabled?
          @callbacks = []
        end
      end
    end
  end
end
