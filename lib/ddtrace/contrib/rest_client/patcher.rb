# typed: true
module Datadog
  module Contrib
    module RestClient
      # Patcher enables patching of 'rest_client' module.
      module Patcher
        include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/ext/app_types'
          require 'ddtrace/contrib/rest_client/request_patch'

          ::RestClient::Request.include(RequestPatch)
        end
      end
    end
  end
end
