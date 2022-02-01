# typed: true
require 'datadog/tracing/contrib/dalli/ext'
require 'datadog/tracing/contrib/dalli/instrumentation'
require 'datadog/tracing/contrib/dalli/integration'
require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
    module Contrib
      module Dalli
        # Patcher enables patching of 'dalli' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Dalli::Server.include(Instrumentation)
          end
        end
      end
    end
  end
end
