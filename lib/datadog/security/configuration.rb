require 'datadog/security/configuration/settings'

module Datadog
  module Security
    # Configuration for Security
    # TODO: this is a trivial implementation, check with shareable code with
    # tracer and other products
    module Configuration
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Configuration DSL implementation
      class DSL
        def initialize
          @instruments = []
        end

        def instrument(name, options = {})
          @instruments << [name, options]
        end

        attr_reader :instruments

        def [](key)
          found = @instruments.find { |k, _| k == key }

          found.last if found
        end
      end

      # class-level methods for Configuration
      module ClassMethods
        def configure
          dsl = DSL.new
          yield dsl
          settings.merge(dsl)
        end

        def settings
          @settings ||= Settings.new
        end
      end
    end
  end
end
