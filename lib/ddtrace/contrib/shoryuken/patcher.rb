require 'ddtrace/contrib/shoryuken/tracer'

module Datadog
  module Contrib
    module Shoryuken
      # Patcher enables patching of 'shoryuken' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:shoryuken)
        end

        def patch
          do_once(:shoryuken) do
            begin
              ::Shoryuken.server_middleware do |chain|
                chain.add Shoryuken::Tracer
              end
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Shoryuken integration: #{e}")
            end
          end
        end
      end
    end
  end
end
