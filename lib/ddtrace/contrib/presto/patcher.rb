# typed: true
require 'datadog/core/utils/only_once'
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/presto/ext'
require 'ddtrace/contrib/presto/instrumentation'

module Datadog
  module Tracing
    module Contrib
      module Presto
        # Patcher enables patching of 'presto-client' module.
        module Patcher
          include Contrib::Patcher

          PATCH_ONLY_ONCE = Core::Utils::OnlyOnce.new

          module_function

          def patched?
            PATCH_ONLY_ONCE.ran?
          end

          def patch
            PATCH_ONLY_ONCE.run do
              begin
                ::Presto::Client::Client.include(Instrumentation::Client)
              rescue StandardError => e
                Datadog.logger.error("Unable to apply Presto integration: #{e}")
              end
            end
          end
        end
      end
    end
  end
end
