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
            require 'ddtrace/contrib/httparty/instrumentation/helpers'
            require 'ddtrace/contrib/httparty/instrumentation/request'

            # patch the HTTParty module
            ::HTTParty::ClassMethods.send(:include, Instrumentation::Helpers)

            # patch the HTTParty::Request class
            ::HTTParty::Request.send(:include, Instrumentation::Request)
          end
        end
      end
    end
  end
end
