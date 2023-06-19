# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Represents an instance of an integration configuration option
      # @public_api
      class Option
        attr_reader \
          :definition

        # Option setting precedence. Higher number means higher precedence.
        module Precedence
          REMOTE_CONFIGURATION = 2
          PROGRAMMATIC = 1
          DEFAULT = 0
        end

        def initialize(definition, context)
          @definition = definition
          @context = context
          @value = nil
          @is_set = false

          # Lowest precedence, to allow for `#set` to always succeed for a brand new `Option` instance.
          @precedence_set = Precedence::DEFAULT
        end

        # Overrides the current value for this option if the `precedence` is equal or higher than
        # the previously set value.
        # The first call to `#set` will always store the value regardless of precedence.
        #
        # @param value [Object] the new value to be associated with this option
        # @param precedence [Precedence] from what precedence order this new value comes from
        def set(value, precedence: Precedence::PROGRAMMATIC)
          return @value if precedence < @precedence_set # Cannot override higher precedence value

          old_value = @value
          (@value = context_exec(value, old_value, &definition.setter)).tap do |v|
            @is_set = true
            @precedence_set = precedence
            context_exec(v, old_value, &definition.on_set) if definition.on_set
          end
        end

        def get
          if @is_set
            @value
          elsif definition.delegate_to
            context_eval(&definition.delegate_to)
          else
            set(default_value, precedence: Precedence::DEFAULT)
          end
        end

        def reset
          @value = if definition.resetter
                     # Don't change @is_set to false; custom resetters are
                     # responsible for changing @value back to a good state.
                     # Setting @is_set = false would cause a default to be applied.
                     context_exec(@value, &definition.resetter)
                   else
                     @is_set = false
                     nil
                   end

          @precedence_set = Precedence::DEFAULT
        end

        def default_value
          if definition.lazy
            context_eval(&definition.default)
          else
            definition.default
          end
        end

        private

        def context_exec(*args, &block)
          @context.instance_exec(*args, &block)
        end

        def context_eval(&block)
          @context.instance_eval(&block)
        end

        # Used for testing
        attr_reader :precedence_set
        private :precedence_set
      end
    end
  end
end
