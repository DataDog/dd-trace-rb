require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/presto/ext'
require 'ddtrace/contrib/presto/instrumentation'

module Datadog
  module Contrib
    module Presto
      # Patcher enables patching of 'presto-client' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:presto)
        end

        def patch
          do_once(:presto) do
            begin
              ::Presto::Client::Client.send(:include, Instrumentation::Client)
            rescue StandardError => e
              Datadog.logger.error("Unable to apply Presto integration: #{e}")
            end
          end
        end
      end
    end
  end
end
