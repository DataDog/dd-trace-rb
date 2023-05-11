require 'set'

module Datadog
  module Core
    module Dependency
      # TODO: remove this test io, use a real logger instead. but Datadog.logger is not available here yet.
      LOGGER = Module.new do
        def self.puts(arg)
        end
      end

      module ComponentMixin
        def setting(init_parameter, config_path, global_registry: Datadog::Core.dependency_registry)
          LOGGER.puts "Declaration at #{caller[0].sub(/:in.*/, '')}: (#{self}), setting(#{config_path}), param:#{init_parameter}, "
          global_registry.register(self, init_parameter, :setting, config_path)
        end

        def component(component_name, parameter: component_name, global_registry: Datadog::Core.dependency_registry)
          LOGGER.puts "Declaration at #{caller[0].sub(/:in.*/, '')}:(#{self}), component(#{component_name}), param:#{component_name}"
          global_registry.register(self, parameter, :component, component_name)
        end

        # No-arg component
        def component_name(self_component_name = Util.to_base_name(self), global_registry: Datadog::Core.dependency_registry)
          self_component_name = self_component_name.to_s
          LOGGER.puts "Declaration at #{caller[0].sub(/:in.*/, '')}: no-arg component #{self_component_name}(#{self})"
          global_registry.register_component(self, self_component_name)
        end
      end

      module Util
        def self.to_base_name(clazz)
          # TODO: review this string manipulation logic. It was mishmashed from different algorithms.
          clazz.name.split('::').last.
            gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
            gsub(/([a-z\d])([A-Z])/, '\1_\2').
            tr("-", "_").
            downcase
        end
      end

      def self.extended(base)
        base.extend(ComponentMixin)
      end

      class Registry
        Key = Struct.new(:type, :dependency)
        Value = Struct.new(:component_class, :init_parameter)

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
          @component_name = {}
          @mutex = Monitor.new # Should be re-entrant
        end

        attr_writer :configuration

        # TODO: this should not be conditional
        # TODO: Registry needs to track configuration changes in batch.
        def configuration
          @configuration || Datadog.configuration
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
            LOGGER.puts "Found existing component `#{component_name}`"
            existing
          else
            @mutex.synchronize do
              # Check again, in case we were waiting for this mutex and another thread has initialized this component
              if (existing = instance_variable_get(:"@#{component_name}")) && !force_init
                LOGGER.puts "Found existing component `#{component_name}`"
                return existing
              end

              LOGGER.puts "Creating new instance of component `#{component_name}`"
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
          # TODO: This is a Hash#dig backport, we should implement a proper configuration access implementation
          config_path.split('.').reduce(configuration) do |value, key|
            value.public_send(key)
          end
          # hash = configuration.options_hash
          # configuration.options_hash.dig(*config_path.split('.').map(&:to_sym))

          # class Hash
          #   def dig(key, *rest)
          # hash = configuration.options_hash
          # val = hash[key]
          # return val if rest.empty? || val == nil
          # val.dig(*rest)
          # end
          # end
        end

        # Eager-loads all registered components.
        # TODO: Not used.
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
        def register(component_class, init_parameter, type, dependency)
          key = Key.new(type, dependency)
          value = Value.new(component_class, init_parameter)

          set = (@dependencies[key] ||= Set.new)
          set.add(value)

          @reverse_dependencies[value] = key

          # Register component lookup if not present
          if !@component_name[component_class] && !@component_lookup.find{ |_, value| value == component_class}
            name = Util.to_base_name(component_class).to_sym
            @component_name[component_class] = name
            @component_lookup[name] = component_class
          end
        end

        # Register a no-arg component.
        # TODO: condense this with #register?
        def register_component(component_class, component_name)
          # key = Key.new(type, dependency)
          # value = Value.new(component_class, nil)

          # set = (@dependencies[key] ||= Set.new)
          # set.add(value)

          # @reverse_dependencies[value] = Set.new

          @component_name[component_class] = component_name.to_sym

          # Override component lookup if present
          @component_lookup[component_name.to_sym] = component_class
        end

        # Shuts down all components.
        # They will be reinitialized with `#resolve` after this call returns.
        def shutdown
          all_components.each do |c|
            shut_down_component(c)
            delete_by_name(c)
          end
          @configuration = nil
          nil
        end

        def shut_down_component(component_name)
          LOGGER.puts "Shutting down component `#{component_name}`"

          component = component_by_name(component_name)
          component.shutdown! if component.respond_to?(:shutdown!)
        end

        def delete_by_name(component_name)
          remove_instance_variable(:"@#{component_name}") if component_by_name(component_name)
        end

        # Applies a batch of configuration changes
        # DEV: @param force_reset_all: Is this ever a good idea? Maybe for testing. Provide changes instead.
        #
        # TODO: only reset components that have been initialized already. There's no reason to initialize everything eagerly.
        def change_settings(config_changes_hash, force_reset_all: false)
          LOGGER.puts "Settings changed!: #{config_changes_hash}, force_reset_all: #{force_reset_all}"
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

            # Datadog.LOGGER.debug { "Update #{update}" }
            # Datadog.LOGGER.debug { "Reset #{reset}" }

            # If we are going to reset an object anyway, don't bother updating any fields
            update.delete_if { |component,|
              reset.include?(@component_name[component.component_class])
            }

            # Apply changes!

            update.each do |value, new_value|
              component = component_by_name(@component_name[value.component_class])
              component.send("#{value.init_parameter}=", new_value)

              LOGGER.puts "Updated `#{@component_name[value.component_class]}.#{value.init_parameter} = #{new_value}`"
            end

            # TODO: extract this `reset` logic below

            # Reset in correct order: leaf components first
            depending_components = reset.map do |component_name|
              component_class = @component_lookup[component_name]

              # Only store in this list components that will be `reset` now.
              # Unmodified components are relevant because we can use their currently existing instance.
              [component_name, @reverse_dependencies.select do |key, value|
                key.component_class == component_class && value.type == :component
              end.map { |_, value| value.dependency } & reset]
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
          component_class = @component_lookup[component_name]
          dependencies = @reverse_dependencies.select { |key, _| key.component_class == component_class } # Can be cached in a reverse-lookup hash
          args, kwargs = to_args(component_name, dependencies)

          opt = kwargs.map { |name, dependency| [name, resolve(dependency)] }.to_h

          # Because of old Rubies, we have to omit `**{}` as keyword arguments as that becomes a positional Hash parameter.
          if opt.empty?
            @component_lookup[component_name].new(*args.map { |_, dependency| resolve(dependency) })
          else
            @component_lookup[component_name].new(*args.map { |_, dependency| resolve(dependency) }, **opt)
          end
        end

        DELEGATION_PARAMETERS = [
          [:rest],
          [:rest, :block],
          [:rest, :keyrest],
          [:rest, :keyrest, :block],
        ].freeze


        # Ruby 2.1 does not support `UnboundMethod#super_method`, which makes finding
        # the non-delegating method harder.
        # Ruby 2.3 `UnboundMethod#super_method` does not work as expected, returning
        # `nil` when there is a super method present.
        if RUBY_VERSION < '2.2' || (RUBY_VERSION >= '2.3' && RUBY_VERSION < '2.4')
          def find_non_delegating_method(clazz, type, method_name)
            clazz.ancestors.each do |c|
              return nil if c == Object # We failed to find a suitable class

              method = (c.send(type, method_name) rescue nil)

              next unless method

              parameters = method.parameters
              param_types = parameters.map(&:first)
              return method unless DELEGATION_PARAMETERS.include?(param_types)
            end

            nil
          end
        else
          # When classes has modules prepended, they can override initializing methods.
          # This methods iterates until it finds a method with non-delegating arguments.
          # DEV: This method should receive the argument `method` directly when
          # DEV: support for Ruby 2.1 is removed.
          def find_non_delegating_method(clazz, type, method_name)
            method = clazz.send(type, method_name)

            while method
              parameters = method.parameters
              param_types = parameters.map(&:first)
              return method unless DELEGATION_PARAMETERS.include?(param_types)

              method = method.super_method
            end
          end
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
          # DEV: replace with `String#match?` as it is much faster, but not available in old rubies.
          # binding.pry if component.methods(false).include?(:new) && component.public_method(:new).source_location == nil
          init_method = if component.methods(false).include?(:new) && component.public_method(:new).source_location && !component.public_method(:new).source_location[0].match(%r{rspec\/mocks\/method_double}) # DEV: rspec-mocks creates a test Class#new method.
                          find_non_delegating_method(component, :public_method, :new)
                        else
                          find_non_delegating_method(component, :instance_method, :initialize)
                          # find_non_delegating_method(component.instance_method(:initialize)) do
                          #   component.instance_method(:initialize)
                          # end
                        end

          if (RUBY_VERSION < '2.2'  || (RUBY_VERSION >= '2.3' && RUBY_VERSION < '2.4')) && init_method.nil?
            # We can't reliable find method parameters in Ruby 2.1 or Ruby 2.3 when prepend is used
            # to wrap a component's class.
            # We have to resort to trusting our argument declaration, despite that being not as trustworthy.
            #
            # Because we don't know if the arguments are positional or keyword, we have pick one option.
            # For the current implementation, we assume that all arguments declared for this component are keyword.
            #
            # DEV: This is unsafe, but Ruby 2.1 & Ruby 2.3 do not provide enough reflection information to
            # DEV: make the checks reliable.
            dependencies.each do |key, dependency|
              kwargs << [key.init_parameter, dependency]
            end
          else
            # Match declared parameters with actual Ruby method signatures.
            init_method.parameters.each do |type, arg_name|
              _, dependency = dependencies.find do |key, _|
                key.init_parameter == arg_name
              end

              unless dependency
                if type == :opt || type == :key || # Optional parameters
                  type == :rest || type == :keyrest #|| # Wildcard parameters
                  type == :block # Block can be omitted

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
          shut_down_component(component_name)

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
            if component.component_class.public_method_defined?("#{component.init_parameter}=")
              # Call setter instead of resetting the whole component
              update << [component, new_value]
            else
              reset << @component_name[component.component_class]
            end
          end

          [update, reset]
        end
      end
    end
  end
end
