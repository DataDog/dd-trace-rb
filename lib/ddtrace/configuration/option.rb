module Datadog
  module Configuration
    # Represents an instance of an integration configuration option
    class Option
      attr_reader \
        :definition

      def initialize(definition, context)
        @definition = definition
        @context = context
        @value = nil
        @is_set = false
      end

      def set(value)
        @value = @context.instance_exec(value, &definition.setter).tap do
          @is_set = true
        end
      end

      def get
        return definition.default_value unless @is_set
        @value
      end

      def reset
        set(definition.default_value)
      end
    end
  end
end
