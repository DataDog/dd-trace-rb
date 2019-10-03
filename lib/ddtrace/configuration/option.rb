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
        @value = if definition.resetter
                   # Don't change @is_set to false; custom resetters are
                   # responsible for changing @value back to a good state.
                   # Setting @is_set = false would cause a default to be applied.
                   @context.instance_exec(@value, &definition.resetter)
                 else
                   @is_set = false
                   nil
                 end
      end
    end
  end
end
