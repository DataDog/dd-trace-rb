# frozen_string_literal: true

# Load tracing
require_relative 'datadog/tracing'
require_relative 'datadog/tracing/contrib'

# Load other products (must follow tracing)
require_relative 'datadog/profiling'
require_relative 'datadog/appsec'
require_relative 'datadog/ci'
require_relative 'datadog/kit'





graph = {}

# dependencies = class_.instance_method(:initialize).parameters.map do |type, name|
#   next unless type == :req || type == :keyreq
#   name
# end

class DependencyRegistry
  Key = Struct.new(:type, :dependency)

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

  Value = Struct.new(:component_name, :init_parameter)

  def change_settings(config_changes_hash)
    @mutex.synchronize do
      # Should be re-entrant

      update = []
      reset = []
      config_changes_hash.each do |config_path, new_value|
        u, r = change_setting(config_path, new_value)

        update += u
        reset += r

        # Recursively reconfigure anythings that depends on components that will be reset.
        reset += reset.flat_map{ |component_name| check_reset_component(component_name)}
      end

      reset.uniq!

      Datadog.logger.debug { "Update #{update}" }
      Datadog.logger.debug { "Reset #{reset}" }

      # If we are going to reset an object anyway, don't bother updating any fields
      update.delete_if { |component,| reset.include?(component.component_name) }

      # Apply changes!

      update.each do |value, new_value|
        component = component_by_name(value.component_name)
        component.send("#{value.init_parameter}=", new_value)

        Datadog.logger.debug { "Updated #{value.component_name}##{value.init_parameter} to #{new_value}" }
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
      root, _ = depending_components.find { |_,dependencies| dependencies.empty? }

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

        depending_components.delete_if { |component_name,| component_name == root}

        root, _ = depending_components.find { |_,dependencies| dependencies.empty? }
      end
    end
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

  def initialize
    @dependencies = {}
    @reverse_dependencies = {}
    @component_lookup = {}
    @mutex = Monitor.new
  end

  def register(component_class, type, init_parameter, dependency, component_name:)
    key = Key.new(type, dependency)
    value = Value.new(component_name.to_sym, init_parameter)

    # @dependencies =
    #   {
    #     { type: :setting, dependency: 'runtime_metrics.enabled' } => { component_name : 'RuntimeMetrics', init_parameter: :enabled },
    #     { type: :component, dependency: 'agent_settings' } => { component_name : 'RuntimeMetrics', init_parameter: :agent_settings }
    #   }

    set = (@dependencies[key] ||= Set.new)
    set.add(value)

    @reverse_dependencies[value] = key

    @component_lookup[component_name.to_sym] = component_class
  end

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

  def resolve_setting(config_path)
    Datadog.configuration.options_hash.dig(*config_path.split('.').map(&:to_sym))
  end

  def resolve_component(component_name, force_init: false)
    if (existing = instance_variable_get(:"@#{component_name}")) && !force_init
      existing
    else
      @mutex.synchronize do
        # Should be re-entrant
        # Check again, in case we were waiting for this mutex and another thread has initialized this component
        if (existing = instance_variable_get(:"@#{component_name}")) && !force_init
          return existing
        end

        component = init_component(component_name)
        instance_variable_set(:"@#{component_name}", component)
      end
    end
  end

  def component_by_name(component_name)
    instance_variable_get(:"@#{component_name}")
  end

  def reset_component(component_name)
    component = component_by_name(component_name)
    component.shutdown! if component.respond_to?(:shutdown!)

    resolve_component(component_name, force_init: true)
  end

  # @dependencies =
  #   {
  #     { type: :setting, dependency: 'runtime_metrics.enabled' } => { component_name : 'RuntimeMetrics', init_parameter: :enabled },
  #     { type: :component, dependency: 'agent_settings' } => { component_name : 'RuntimeMetrics', init_parameter: :agent_settings }
  #   }



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
    component.instance_method(:initialize).parameters.each do |type, arg_name|
      _, dependency = dependencies.find do |key, _|
        key.init_parameter == arg_name
      end

      unless dependency
        raise "No container registered for #{component_name}#initialize argument #{arg_name}"
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

  def resolve_all
    # Find all components and resolve them
    # Skip already resolved ones (which will happen automatically because of how resolve_component is implemented)
    all_components.each { |component_name| resolve_component(component_name) }
  end
end

module Datadog
  def self.dependencies
    @dependency_registry ||= DependencyRegistry.new
  end
end

module Util
  def self.to_underscore(str)
    str.gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      tr("-", "_").
      downcase
  end
end

module ComponentMixin
  def setting(init_parameter, config_path, global_registry: Datadog.dependencies, self_component_name: Util.to_underscore(name))
    global_registry.register(self, :setting, init_parameter, config_path, component_name: self_component_name)
  end

  def component(component_name, global_registry: Datadog.dependencies, self_component_name: Util.to_underscore(name))
    global_registry.register(self, :component, component_name, component_name, component_name: self_component_name)
  end
end

# Declare ddtrace components

module Datadog
  module Settings
    # Our existing settings
    'agent.host'
    'agent.port'
    'runtime_metrics.enabled'
    'tracing.enabled'
    'sampling.rules'
  end
end

class Tracer
  extend ComponentMixin

  setting(:enabled, 'tracing.enabled')
  component(:sampler)
  component(:agent_settings) # Datadog.internal.components[:agent_settings]
  component(:writer)
  def initialize(enabled, agent_settings, sampler, writer)
    puts "New Tracer"
    @enabled = enabled
    @agent_settings = agent_settings
    @sampler = sampler
    @writer = writer
  end
end

class Sampler
  extend ComponentMixin

  setting(:rate_limit,'tracing.sampling.rate_limit')
  def initialize(rate_limit)
    puts "New Sampler"
    @rate_limit = rate_limit
  end

  def rate_limit=(limit)
    # Trivial to update at runtime
    @rate_limit = limit
  end
end

class Writer
  extend ComponentMixin

  component(:agent_settings)
  def initialize(agent_settings)
    puts "New Writer"
  end
end

class AgentSettings
  extend ComponentMixin

  setting(:host, 'agent.host')
  setting(:port, 'agent.port')
  def initialize(host, port)
    puts "New AgentSettings"
    @host = host
    @port = port
  end
end

class RuntimeMetrics
  extend ComponentMixin

  component(:agent_settings) # Datadog.internal.components[:agent_settings]
  setting(:enabled, 'runtime_metrics.enabled')
  def initialize(enabled, agent_settings)
    puts "New RuntimeMetrics"
    @enabled = enabled
    @agent_settings = agent_settings
  end
end

Datadog.configuration.diagnostics.debug = true

Datadog.dependencies.resolve_all
# puts Datadog.dependencies.change_settings({ 'tracing.sampling.rate_limit' => 0.5 }) #, 'runtime_metrics.enabled' => false })
# Datadog.dependencies.change_settings({ 'agent.host' => 'not.local.host' })
# puts Datadog.dependencies.change_settings({ 'tracing.sampling.rate_limit' => 0.5, 'runtime_metrics.enabled' => false })
puts Datadog.dependencies.change_settings({ 'agent.host' => 'not.local.host', 'runtime_metrics.enabled' => false })

