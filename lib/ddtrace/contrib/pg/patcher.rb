require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/pg/connection'

module Datadog
  module Contrib
    module Pg
      # Patcher enables patching of 'pg' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:pg)
        end

        def patch
          do_once(:pg) do
            begin
              patch_pg_client
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply pg integration: #{e}")
            end
          end
        end

        def patch_pg_client
          ::PG::Connection.send(:include, Connection)
        end
      end
    end
  end
end
