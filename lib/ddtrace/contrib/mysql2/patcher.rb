require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/mysql2/instrumentation'

module Datadog
  module Contrib
    module Mysql2
      # Patcher enables patching of 'mysql2' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:mysql2)
        end

        def patch
          do_once(:mysql2) do
            begin
              patch_mysql2_client
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply mysql2 integration: #{e}")
            end
          end
        end

        def patch_mysql2_client
          ::Mysql2::Client.send(:include, Instrumentation)
        end
      end
    end
  end
end
