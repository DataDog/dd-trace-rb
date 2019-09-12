module Datadog
  module Contrib
    module Configuration
      # Represents an instance of a configurable integration
      class Integration
        attr_reader \
          :definition,
          :callbacks

        def initialize(definition, context)
          @definition = definition
          @context = context
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

        def defaults_applied?
          @defaults_applied == true
        end

        def configure(*args, &block)
          if args.first == false
            disable!
          elsif args.first == true
            enable!
          elsif args.any? || block_given?
            # Configuration implies the integration is enabled.
            # Ensure this integration is enabled.
            enable! unless enabled?

            if definition.defer?
              add_callback(*args, &block)
            else
              apply_defaults! unless defaults_applied?
              apply!(*args, &block)
            end
          end
        end

        # Add a callback that applies configuration
        # when the integration is activated.
        def add_callback(*args, &block)
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

        def apply_defaults!
          unless definition.default.nil?
            apply! do |*args|
              # Ensure it executes in the context of the settings object
              @context.instance_exec(*args, &definition.default)
            end

            @defaults_applied = true
          end
        end

        def apply_callbacks!
          callbacks.each(&:call)
        end

        # Apply configuration and activate the integration.
        # Invoked by integrations that defer configuration/activation
        # of this integration to a specific time.
        def apply_and_activate!(*args, &block)
          return unless enabled?

          # First apply any default settings defined in the configuration
          apply_defaults! unless defaults_applied?

          # Then apply all configuration callbacks
          apply_callbacks!

          # Then apply any supplied configuration (as an override)
          apply!(*args, &block) if args.any? || block_given?

          # Then activate the integration
          activate!
        end

        def activate!
          return unless enabled?
          Datadog.configuration.use(definition.name)
        end

        def reset
          @enabled = definition.enabled?
          @callbacks = []
          @defaults_applied = false
        end
      end
    end
  end
end
