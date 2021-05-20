require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/presto/ext'
require 'ddtrace/contrib/presto/instrumentation'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    module Presto
      # Patcher enables patching of 'presto-client' module.
      module Patcher
        include Contrib::Patcher

        PATCH_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

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
