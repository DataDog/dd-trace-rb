module Datadog
  module Contrib
    module Configuration
      # Represents a definition for an integration configuration option
      class OptionDefinition
        IDENTITY = ->(x) { x }

        attr_reader \
          :default,
          :depends_on,
          :lazy,
          :name,
          :setter

        def initialize(name, meta = {}, &block)
          @default = meta[:default]
          @depends_on = meta[:depends_on] || []
          @lazy = meta[:lazy] || false
          @name = name.to_sym
          @setter = meta[:setter] || block || IDENTITY
        end

        def default_value
          lazy ? @default.call : @default
        end
      end
    end
  end
end
