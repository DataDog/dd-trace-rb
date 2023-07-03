# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Represents an instance of an integration configuration option
      # @public_api
      class Option
        attr_reader :definition

        # Option setting precedence. Higher number means higher precedence.
        module Precedence
          # Remote configuration provided through the Datadog app.
          REMOTE_CONFIGURATION = [2, :remote_configuration].freeze

          # Configuration provided in Ruby code, in this same process.
          PROGRAMMATIC = [1, :programmatic].freeze

          # Configuration that comes either from environment variables,
          # or fallback values.
          DEFAULT = [0, :default].freeze
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
          # Cannot override higher precedence value
          if precedence[0] < @precedence_set[0]
            Datadog.logger.info do
              "Option '#{definition.name}' not changed to '#{value}' (precedence: #{precedence[1]}) because the higher " \
                "precedence value '#{@value}' (precedence: #{@precedence_set[1]}) was already set."
            end

            return @value
          end

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
          if definition.default.instance_of?(Proc)
            context_eval(&definition.default)
          else
            definition.experimental_default_proc || definition.default
          end
        end

        def default_precedence?
          precedence_set == Precedence::DEFAULT
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
