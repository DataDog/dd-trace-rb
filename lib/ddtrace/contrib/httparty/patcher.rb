module Datadog
  module Contrib
    module HTTParty
      # Patcher enables patching of 'httparty' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:httparty)
        end

        def patch
          do_once(:httparty) do
            require 'ddtrace/contrib/httparty/module_patch'
            require 'ddtrace/contrib/httparty/request_patch'

            # patch the HTTParty module
            ::HTTParty::ClassMethods.send(:include, ModulePatch)

            # patch the HTTParty::Request class
            ::HTTParty::Request.send(:include, RequestPatch)
          end
        end
      end
    end
  end
end
