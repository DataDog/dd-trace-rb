module Datadog
  InvalidOptionError = Class.new(StandardError)
  # Configurable provides configuration methods for a given class/module
  module Configurable
    IDENTITY = ->(x) { x }

    def self.included(base)
      base.singleton_class.send(:include, ClassMethods)
    end

    # ClassMethods
    module ClassMethods
      def set_option(name, value)
        __assert_valid!(name)

        __options[name][:value] = __options[name][:setter].call(value)
        __options[name][:set_flag] = true
      end

      def get_option(name)
        __assert_valid!(name)

        return __default_value(name) unless __options[name][:set_flag]

        __options[name][:value]
      end

      def to_h
        __options.each_with_object({}) do |(key, _), hash|
          hash[key] = get_option(key)
        end
      end

      def reset_options!
        __options.each do |name, meta|
          set_option(name, meta[:default])
        end
      end

      def sorted_options
        Configuration::Resolver.new(__dependency_graph).call
      end

      private

      def option(name, meta = {}, &block)
        name = name.to_sym
        meta[:setter] ||= (block || IDENTITY)
        meta[:depends_on] ||= []
        meta[:lazy] ||= false
        __options[name] = meta
      end

      def __options
        @__options ||= {}
      end

      def __assert_valid!(name)
        return if __options.key?(name)
        raise(InvalidOptionError, "#{__pretty_name} doesn't have the option: #{name}")
      end

      def __pretty_name
        entry = Datadog.registry.find { |el| el.klass == self }

        return entry.name if entry

        to_s
      end

      def __dependency_graph
        __options.each_with_object({}) do |(name, meta), graph|
          graph[name] = meta[:depends_on]
        end
      end

      def __default_value(name)
        return __options[name][:default].call if __options[name][:lazy]
        __options[name][:default]
      end
    end
  end
end
