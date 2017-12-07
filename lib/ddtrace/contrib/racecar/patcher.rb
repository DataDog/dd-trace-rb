module Datadog
  module Contrib
    module Racecar
      module Patcher
        include Base
        register_as :racecar
        option :service_name, default: 'racecar'

        module_function

        def patch
          return patched? if patched? || !defined?(::Racecar)

          require_relative 'tracer'

          ::Racecar.singleton_class.class_eval do
            alias_method :__instrumenter, :instrumenter

            def instrumenter
              @instrumenter ||= Datadog::Contrib::Racecar::Tracer.new(__instrumenter)
            end
          end

          @patched = true
        end

        def patched?
          @patched ||= false
        end
      end
    end
  end
end
