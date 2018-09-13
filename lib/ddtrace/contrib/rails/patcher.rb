require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rails
      # Patcher for Rails
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:rails)
        end

        def patch
          do_once(:rails) do
            require_relative 'framework'
          end
        rescue => e
          Datadog::Tracer.log.error("Unable to apply Rails integration: #{e}")
        end
      end
    end
  end
end
