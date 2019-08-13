require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_support/cache/patcher'

module Datadog
  module Contrib
    module ActiveSupport
      # Patcher enables patching of 'active_support' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:active_support)
        end

        def patch
          do_once(:active_support) do
            begin
              Cache::Patcher.patch
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Active Support integration: #{e}")
            end
          end
        end
      end
    end
  end
end
