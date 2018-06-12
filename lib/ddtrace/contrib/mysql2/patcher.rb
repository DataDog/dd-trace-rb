require 'ddtrace/contrib/mysql2/client'

module Datadog
  module Contrib
    module Mysql2
      # Mysql2 patcher
      module Patcher
        include Base

        register_as :mysql2
        option :service_name, default: 'mysql2'
        option :tracer, default: Datadog.tracer

        @patched = false

        module_function

        def patch
          return @patched if patched? || !compatible?

          patch_mysql2_client

          @patched = true
        rescue StandardError => e
          Tracer.log.error("Unable to apply mysql2 integration: #{e}")
          @patched
        end

        def patched?
          @patched
        end

        def compatible?
          RUBY_VERSION >= '2.0.0' && defined?(::Mysql2)
        end

        def patch_mysql2_client
          ::Mysql2::Client.send(:include, Client)
        end
      end
    end
  end
end
