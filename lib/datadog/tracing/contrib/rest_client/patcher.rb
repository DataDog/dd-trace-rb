# typed: true
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/rest_client/integration'

module Datadog
  module Tracing
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
            require 'datadog/tracing/contrib/rest_client/request_patch'

            ::RestClient::Request.include(RequestPatch)
          end
        end
      end
    end
  end
end
