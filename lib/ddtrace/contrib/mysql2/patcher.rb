require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/mysql2/instrumentation'

module Datadog
  module Contrib
    module Mysql2
      # Patcher enables patching of 'mysql2' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          patch_mysql2_client
        end

        def patch_mysql2_client
          ::Mysql2::Client.send(:include, Instrumentation)
        end
      end
    end
  end
end
