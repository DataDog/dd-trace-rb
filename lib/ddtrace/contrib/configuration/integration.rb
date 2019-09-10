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
            if definition.defer?
              add_apply_callback(*args, &block)
            else
              apply!(*args, &block)
            end
          end
        end

        # Add a callback that applies configuration
        # when the integration is activated.
        def add_apply_callback(*args, &block)
          callbacks << proc { apply!(*args, &block) }
        end

        # Apply configuration to integration
        def apply!(*args, &block)
          Datadog.configuration.set(
            definition.name,
            *args,
            &block
          )
        end

        def activate!
          Datadog.configuration.use(definition.name)
        end

        # Apply configuration and activate the integration
        def apply_and_activate!(*args, &block)
          return unless enabled?

          # First apply any supplied configuration to the integration
          apply!(*args, &block)

          # Then apply all configuration callbacks
          callbacks.each(&:call)

          # Then activate the integration
          activate!
        end

        def reset
          @enabled = definition.enabled?
          @callbacks = []
        end
      end
    end
  end
end
