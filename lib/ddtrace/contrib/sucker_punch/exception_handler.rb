require 'sucker_punch'

module Datadog
  module Contrib
    module SuckerPunch
      # Patches `sucker_punch` exception handling
      module ExceptionHandler
        METHOD = ->(e, *) { raise(e) }

        module_function

        def patch!
          ::SuckerPunch.class_eval do
            class << self
              alias_method :__exception_handler, :exception_handler

              def exception_handler
                ::Datadog::Contrib::SuckerPunch::ExceptionHandler::METHOD
              end
            end
          end
        end
      end
    end
  end
end
