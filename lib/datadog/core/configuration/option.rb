# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Represents an instance of an integration configuration option
      # @public_api
      class Option
        attr_reader :definition

        # Option setting precedence.
        module Precedence
          # Represents an Option precedence level.
          # Each precedence has a `numeric` value; higher values means higher precedence.
          # `name` is for inspection purposes only.
          Value = Struct.new(:numeric, :name) do
            include Comparable

            def <=>(other)
              return nil unless other.is_a?(Value)

              numeric <=> other.numeric
            end
          end

          # Remote configuration provided through the Datadog app.
          REMOTE_CONFIGURATION = Value.new(2, :remote_configuration).freeze

          # Configuration provided in Ruby code, in this same process.
          PROGRAMMATIC = Value.new(1, :programmatic).freeze

          # Configuration that comes either from environment variables,
          # or fallback values.
          DEFAULT = Value.new(0, :default).freeze

          # All precedences, sorted from highest to lowest
          LIST = [REMOTE_CONFIGURATION, PROGRAMMATIC, DEFAULT].freeze
        end

        def initialize(definition, context)
          @definition = definition
          @context = context
          @value = nil
          @is_set = false

          # One value is stored per precedence, to allow unsetting a higher
          # precedence value and falling back to a lower precedence one.
          @value_per_precedence = Hash.new(UNSET)

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
          # Is there a higher precedence value set?
          if @precedence_set > precedence
            # This should be uncommon, as higher precedence values tend to
            # happen later in the application lifecycle.
            Datadog.logger.info do
              "Option '#{definition.name}' not changed to '#{value}' (precedence: #{precedence.name}) because the higher " \
                "precedence value '#{@value}' (precedence: #{@precedence_set.name}) was already set."
            end

            # But if it happens, we have to store the lower precedence value `value`
            # because it's possible to revert to it by `#unset`ting
            # the existing, higher-precedence value.
            # Effectively, we always store one value pre precedence.
            @value_per_precedence[precedence] = value

            return @value
          end

          internal_set(value, precedence)
        end

        def unset(precedence)
          @value_per_precedence[precedence] = UNSET

          # If we are unsetting the currently active value, we have to restore
          # a lower precedence one...
          if precedence == @precedence_set
            # Find a lower precedence value that is already set.
            Precedence::LIST.each do |p|
              # DEV: This search can be optimized, but the list is small, and unset is
              # DEV: only called from direct user interaction in the Datadog UI.
              next unless p < precedence

              # Look for value that is set.
              # The hash `@value_per_precedence` has a custom default value of `UNSET`.
              if (value = @value_per_precedence[p]) != UNSET
                internal_set(value, p)
                return nil
              end
            end

            # If no value is left to fall back on, reset this option
            reset
          end

          # ... otherwise, we are either unsetting a higher precedence value that is not
          # yet set, thus there's nothing to do; or we are unsetting a lower precedence
          # value, which also does not change the current value.
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

          # Reset back to the lowest precedence, to allow all `set`s to succeed right after a reset.
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

        # Directly manipulates the current value and currently set precedence.
        def internal_set(value, precedence)
          old_value = @value
          (@value = context_exec(value, old_value, &definition.setter)).tap do |v|
            @is_set = true
            @precedence_set = precedence
            @value_per_precedence[precedence] = v
            context_exec(v, old_value, &definition.on_set) if definition.on_set
          end
        end

        def context_exec(*args, &block)
          @context.instance_exec(*args, &block)
        end

        def context_eval(&block)
          @context.instance_eval(&block)
        end

        # Used for testing
        attr_reader :precedence_set
        private :precedence_set

        # Anchor object that represents a value that is not set.
        # This is necessary because `nil` is a valid value to be set.
        UNSET = Object.new
        private_constant :UNSET
      end
    end
  end
end
