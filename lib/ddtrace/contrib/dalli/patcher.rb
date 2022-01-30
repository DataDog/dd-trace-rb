# typed: true
require 'ddtrace/contrib/dalli/ext'
require 'ddtrace/contrib/dalli/instrumentation'
require 'ddtrace/contrib/dalli/integration'
require 'ddtrace/contrib/patcher'

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
