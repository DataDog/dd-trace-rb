module Datadog
  module Core
    module Dependency
      module ComponentMixin
        def setting(init_parameter, config_path, global_registry: Datadog::Core.dependency_registry, self_component_name: Util.to_base_name(self))
          puts "Declaration at #{caller[0].sub(/:in.*/, '')}: #{self_component_name}(#{self}), setting(#{config_path}), param:#{init_parameter}, "
          global_registry.register(self, self_component_name, init_parameter, :setting, config_path)
        end

        def component(component_name, global_registry: Datadog::Core.dependency_registry, self_component_name: Util.to_base_name(self))
          puts "Declaration at #{caller[0].sub(/:in.*/, '')}: #{self_component_name}(#{self}), component(#{component_name}), param:#{component_name}"
          global_registry.register(self, self_component_name, component_name, :component, component_name)
        end

        # No-arg component
        def component_name(self_component_name = Util.to_base_name(self), global_registry: Datadog::Core.dependency_registry)
          puts "Declaration at #{caller[0].sub(/:in.*/, '')}: no-arg component #{self_component_name}(#{self})"
          self.instance_variable_set(:@dependency_component_name, self_component_name)
          global_registry.register_component(self, self_component_name)
        end

        module Util
          def self.to_base_name(clazz)
            existing_name = clazz.instance_variable_get(:@dependency_component_name)
            return existing_name if existing_name

            # TODO: review this string manipulation logic. It was mishmashed from different algorithms.
            clazz.name.split('::').last.
              gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
              gsub(/([a-z\d])([A-Z])/, '\1_\2').
              tr("-", "_").
              downcase
          end
        end
      end

      def self.extended(base)
        base.extend(ComponentMixin)
      end

      class Registry
        Key = Struct.new(:type, :dependency)
        Value = Struct.new(:component_name, :init_parameter)

        class SettingKey
          def self.new(dependency)
            Key.new(:setting, dependency)
          end
        end

        class ComponentKey < Key
          def self.new(dependency)
            Key.new(:component, dependency)
          end
        end

        def initialize
          @dependencies = {}
          @reverse_dependencies = {}
          @component_lookup = {}
          @mutex = Monitor.new # Should be re-entrant
        end

        # Returns the provided component by name.
        #
        # The component (and its dependencies) are initialized if needed.
        # If already initialized, the existing instance is returned.
        #
        # Examples:
        # Datadog.dependency_registry.resolve_component(:tracer)
        # Datadog.dependency_registry.resolve_component(:runtime_metrics)
        # Datadog.dependency_registry.resolve_component(:sampler)
        def resolve_component(component_name, force_init: false)
          if (existing = instance_variable_get(:"@#{component_name}")) && !force_init
            puts "Found existing component `#{component_name}`"
            existing
          else
            @mutex.synchronize do
              # Check again, in case we were waiting for this mutex and another thread has initialized this component
              if (existing = instance_variable_get(:"@#{component_name}")) && !force_init
                puts "Found existing component `#{component_name}`"
                return existing
              end

              puts "Creating new instance of component `#{component_name}`"
              component = init_component(component_name)
              instance_variable_set(:"@#{component_name}", component)
            end
          end
        end

        # Returns the provided configuration by path.
        #
        # Examples:
        # Datadog.dependency_registry.resolve_setting('tracing.enabled')
        # Datadog.dependency_registry.resolve_setting('agent.host')
        # Datadog.dependency_registry.resolve_setting('tracing.sampling.rate_limit')
        def resolve_setting(config_path)
          Datadog.configuration.options_hash.dig(*config_path.split('.').map(&:to_sym))
        end

        # Eager-loads all registered components.
        def resolve_all
          # Find all components and resolve them
          # Skip already resolved ones (which will happen automatically because of how resolve_component is implemented)
          all_components.each { |component_name| resolve_component(component_name) }
        end

        # DSL to register a new initialization parameter for a component.
        #
        # Examples:
        # setting(:host, 'agent.host') # Invokes `register(MyComponent, 'my_component', :host, :setting, 'agent.host')
        # component(:sampler) # Invokes `register(MyComponent, 'my_component', :sampler, :component, :sampler)
        def register(component_class, component_name, init_parameter, type, dependency)
          key = Key.new(type, dependency)
          value = Value.new(component_name.to_sym, init_parameter)

          set = (@dependencies[key] ||= Set.new)
          set.add(value)

          @reverse_dependencies[value] = key

          @component_lookup[component_name.to_sym] = component_class
        end

        # Register a no-arg component.
        # TODO: condense this with #register?
        def register_component(component_class, component_name)
          # key = Key.new(type, dependency)
          value = Value.new(component_name.to_sym, nil)

          # set = (@dependencies[key] ||= Set.new)
          # set.add(value)

          @reverse_dependencies[value] = Set.new

          @component_lookup[component_name.to_sym] = component_class
        end

        # Applies a batch of configuration changes
        # DEV: @param force_reset_all: Is this ever a good idea? Maybe for testing. Provide changes instead.
        def change_settings(config_changes_hash, force_reset_all: false)
          puts "Settings changed!: #{config_changes_hash}, force_reset_all: #{force_reset_all}"
          @mutex.synchronize do
            update = []
            reset = []

            config_changes_hash.each do |config_path, new_value|
              new_updates, new_resets = change_setting(config_path, new_value)

              update += new_updates
              reset += new_resets

              # Recursively reconfigure anythings that depends on components that will be reset.
              reset += reset.flat_map { |component_name| check_reset_component(component_name) }
            end

            # DEV: wip hack to facility resetting everything
            if force_reset_all
              reset = all_components
            end

            # No need to reset components more than once
            reset.uniq!

            # Datadog.logger.debug { "Update #{update}" }
            # Datadog.logger.debug { "Reset #{reset}" }

            # If we are going to reset an object anyway, don't bother updating any fields
            update.delete_if { |component,| reset.include?(component.component_name) }

            # Apply changes!

            update.each do |value, new_value|
              component = component_by_name(value.component_name)
              component.send("#{value.init_parameter}=", new_value)

              puts "Updated `#{value.component_name}.#{value.init_parameter} = #{new_value}`"
            end

            # TODO: extract this `reset` logic below

            # Reset in correct order: leaf components first
            depending_components = reset.map do |component_name|
              # Only store in this list components that will be `reset` now.
              # Unmodified components are relevant because we can use their currently existing instance.
              [component_name, @reverse_dependencies.select { |key, value| key.component_name == component_name && value.type == :component }.map { |_, value| value.dependency } & reset]
            end.to_h

            # depending_components.sort_by! { |_, dependencies| dependencies.size }

            # Start with a root component: one that does not depend on other components.
            root, _ = depending_components.find { |_, dependencies| dependencies.empty? }

            # If there's none, we have a circular dependency which is a fatal issue.
            if !reset.empty? && !root
              raise "Circular dependency between the following components: #{reset}"
            end

            # remaining = reset.dup
            # remaining -= root

            while root
              reset_component(root)
              Datadog.logger.debug { "Reset #{root} due to configuration changes" }

              depending_components.each do |_, dependencies|
                dependencies.delete(root)
              end

              depending_components.delete_if { |component_name,| component_name == root }

              root, _ = depending_components.find { |_, dependencies| dependencies.empty? }
            end
          end
        end

        private

        def resolve(key)
          case key.type
          when :setting
            resolve_setting(key.dependency)
          when :component
            resolve_component(key.dependency)
          else
            raise "Bad dependency resolution type #{type} for name #{name}"
          end
        end

        def init_component(component_name)
          dependencies = @reverse_dependencies.select { |key, _| key.component_name == component_name } # Can be cached in a reverse-lookup hash
          args, kwargs = to_args(component_name, dependencies)

          @component_lookup[component_name].new(
            *args.map { |_, dependency| resolve(dependency) },
            **kwargs.map { |name, dependency| [name, resolve(dependency)] }.to_h,
          )
        end

        def to_args(component_name, dependencies)
          args = []
          kwargs = []

          # TODO: swap loop order, to ensure position arguments are in correct order
          component = @component_lookup[component_name]
          unless component
            raise "Component #{component_name} not declared!"
          end

          # Does this method override `self.new`?
          # DEV: `Object#public_methods(false)` returns a false positive for :new. A Ruby bug?
          init_method = if component.methods(false).include?(:new)
                          component.public_method(:new)
                        else
                          component.instance_method(:initialize)
                        end
          init_method.parameters.each do |type, arg_name|
            _, dependency = dependencies.find do |key, _|
              key.init_parameter == arg_name
            end

            unless dependency
              if type == :opt || type == :key || # Optional parameters
                type == :rest || type == :keyrest # Wildcard parameters

                next # It's safe to skip and let the parameter defaults be used.
              end

              raise "No container registered for #{component_name} `#{component.name}#initialize` argument `#{arg_name}`"
            end

            case type
            when :req, :opt
              args << [arg_name, dependency]
            when :keyreq, :key
              kwargs << [arg_name, dependency]
            end
          end

          [args, kwargs]
        end

        def all_components
          @component_lookup.keys
        end

        def component_by_name(component_name)
          instance_variable_get(:"@#{component_name}")
        end

        def reset_component(component_name)
          puts "Shutting down component `#{component_name}`"

          component = component_by_name(component_name)
          component.shutdown! if component.respond_to?(:shutdown!)

          resolve_component(component_name, force_init: true)
        end

        def check_reset_component(component_name)
          key = ComponentKey.new(component_name)
          (@dependencies[key] || []).flat_map do |component|
            [component.component_name] + check_reset_component(component.component_name)
          end
        end

        def change_setting(config_path, new_value)
          key = SettingKey.new(config_path)

          update = []
          reset = []

          @dependencies[key].each do |component|
            component_class = @component_lookup[component.component_name]

            if component_class.public_method_defined?("#{component.init_parameter}=")
              # Call setter instead of resetting the whole component
              update << [component, new_value]
            else
              reset << component.component_name
            end
          end

          [update, reset]
        end
      end
    end
  end
end
