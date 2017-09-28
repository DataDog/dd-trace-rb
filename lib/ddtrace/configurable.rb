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
        assert_valid!(name)

        options[name][:value] = options[name][:setter].call(value)
      end

      def get_option(name)
        assert_valid!(name)

        options[name][:value] || options[name][:default]
      end

      def to_h
        options.each_with_object({}) do |(key, meta), hash|
          hash[key] = meta[:value]
        end
      end

      def reset_options!
        options.each do |name, meta|
          set_option(name, meta[:default])
        end
      end

      private

      def option(name, meta = {})
        name = name.to_sym
        meta[:setter] ||= IDENTITY
        options[name] = meta
      end

      def options
        @options ||= {}
      end

      def assert_valid!(name)
        return if options.key?(name)
        raise(InvalidOptionError, "#{pretty_name} doesn't have the option: #{name}")
      end

      def pretty_name
        entry = Datadog.registry.find { |el| el.klass == self }

        return entry.name if entry

        to_s
      end
    end
  end
end
