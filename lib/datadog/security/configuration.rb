require 'datadog/security/configuration/settings'

module Datadog
  module Security
    module Configuration
      def self.included(base)
        base.extend(ClassMethods)
      end

      class DSL
        def initialize
          @uses = []
        end

        def use(name, options = {})
          p [name, options]
          @uses << [name, options]
        end

        def uses
          @uses
        end

        def [](key)
          found = @uses.select { |k, v| k == key }.first

          found.last if found
        end
      end

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
