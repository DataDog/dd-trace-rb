# frozen_string_literal: true

require_relative '../utils/safe_dup'

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
          (@value = context_exec(validate_type(value), old_value, &definition.setter)).tap do |v|
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
            set_value_from_env_or_default
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
            definition.experimental_default_proc || Core::Utils::SafeDup.frozen_or_dup(definition.default)
          end
        end

        def default_precedence?
          precedence_set == Precedence::DEFAULT
        end

        private

        def coerce_env_variable(value)
          case @definition.type
          when :int
            # DEV-2.0: Change to a more strict coercion method. Integer(value).
            value.to_i
          when :float
            # DEV-2.0: Change to a more strict coercion method. Float(value).
            value.to_f
          when :array
            values = if value.include?(',')
                       value.split(',')
                     else
                       value.split(' ') # rubocop:disable Style/RedundantArgument
                     end

            values.map! do |v|
              v.gsub!(/\A[\s,]*|[\s,]*\Z/, '')

              v.empty? ? nil : v
            end

            values.compact!
            values
          when :bool
            string_value = value
            string_value = string_value.downcase
            string_value == 'true' || string_value == '1' # rubocop:disable Style/MultipleComparison
          when :string, NilClass
            value
          else
            raise ArgumentError, "The option #{@definition.name} is using an unknown type option `#{@definition.type}`"
          end
        end

        def validate_type(value)
          raise_error = false

          valid_type = validate(@definition.type, value)

          unless valid_type
            raise_error = if @definition.type_options[:nil]
                            !value.is_a?(NilClass)
                          else
                            true
                          end
          end

          if raise_error
            error_msg = if @definition.type_options[:nil]
                          "The option #{@definition.name} support this type `#{@definition.type}` "\
                                      "and `nil` but the value provided is #{value.class}"
                        else
                          "The option #{@definition.name} support this type `#{@definition.type}` "\
                          "but the value provided is #{value.class}"
                        end

            raise ArgumentError, error_msg
          end

          value
        end

        def validate(type, value)
          case type
          when :string
            value.is_a?(String)
          when :int, :float
            value.is_a?(Numeric)
          when :array
            value.is_a?(Array)
          when :hash
            value.is_a?(Hash)
          when :bool
            value.is_a?(TrueClass) || value.is_a?(FalseClass)
          when :proc
            value.is_a?(Proc)
          when :symbol
            value.is_a?(Symbol)
          when NilClass
            true
          else
            raise ArgumentError, "The option #{@definition.name} is using an unknown type option `#{@definition.type}`"
          end
        end

        def context_exec(*args, &block)
          @context.instance_exec(*args, &block)
        end

        def context_eval(&block)
          @context.instance_eval(&block)
        end

        def set_value_from_env_or_default
          value = nil
          precedence = nil

          if definition.env_var && ENV[definition.env_var]
            value = coerce_env_variable(ENV[definition.env_var])
            precedence = Precedence::PROGRAMMATIC
          end

          if value.nil? && definition.deprecated_env_var && ENV[definition.deprecated_env_var]
            value = coerce_env_variable(ENV[definition.deprecated_env_var])
            precedence = Precedence::PROGRAMMATIC

            Datadog::Core.log_deprecation do
              "#{definition.deprecated_env_var} environment variable is deprecated, use #{definition.env_var} instead."
            end
          end

          option_value = value.nil? ? default_value : value

          set(option_value, precedence: precedence || Precedence::DEFAULT)
        end

        # Used for testing
        attr_reader :precedence_set
        private :precedence_set
      end
    end
  end
end
