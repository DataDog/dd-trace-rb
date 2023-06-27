require_relative '../patcher'
require_relative 'ext'
require_relative 'instrumentation'

module Datadog
  module Tracing
    module Contrib
      module Pubsub
        # Patcher enables patching of 'pubsub' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            begin
              ::Google::Cloud::PubSub::Topic.include(Instrumentation::Publisher)
              ::Google::Cloud::PubSub::Subscription.include(Instrumentation::Consumer)
            rescue StandardError => e
              Datadog.logger.error("Unable to apply PubSub integration: #{e}")
            end
          end
        end
      end
    end
  end
end
