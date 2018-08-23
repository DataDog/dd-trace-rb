module Datadog
  module Contrib
    module RestClient
      # RestClient integration
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:rest_client)
        end

        def patch
          do_once(:rest_client) do
            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/rest_client/request_patch'

            ::RestClient::Request.send(:include, RequestPatch)
          end
        end
      end
    end
  end
end
