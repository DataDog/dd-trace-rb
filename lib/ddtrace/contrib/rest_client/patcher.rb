module Datadog
  module Contrib
    module RestClient
      # Patcher enables patching of 'rest_client' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/ext/app_types'
          require 'ddtrace/contrib/rest_client/request_patch'

          ::RestClient::Request.send(:include, RequestPatch)
        end
      end
    end
  end
end
