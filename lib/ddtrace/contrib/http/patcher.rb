require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/http/ext'
require 'ddtrace/contrib/http/instrumentation'

module Datadog
  module Contrib
    # Datadog Net/HTTP integration.
    module HTTP
      # Patcher enables patching of 'net/http' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        # patch applies our patch if needed
        def patch
          ::Net::HTTP.send(:include, Instrumentation)
        end
      end
    end
  end
end
