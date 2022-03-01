# typed: true

require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/http/ext'
require 'datadog/tracing/contrib/http/instrumentation'

module Datadog
  module Tracing
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
            ::Net::HTTP.include(Instrumentation)
          end
        end
      end
    end
  end
end
