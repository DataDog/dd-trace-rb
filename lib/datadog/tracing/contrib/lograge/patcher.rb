# frozen_string_literal: true

require_relative '../patcher'
require_relative 'instrumentation'

module Datadog
  module Tracing
    module Contrib
      # Datadog Lograge integration.
      module Lograge
        # Patcher enables patching of 'lograge' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          # patch applies our patch
          def patch
            # ActiveSupport::TaggedLogging is the default Rails logger since Rails 5
            if defined?(::ActiveSupport::TaggedLogging::Formatter) &&
                ::Lograge::LogSubscribers::ActionController
                    .logger&.formatter.is_a?(::ActiveSupport::TaggedLogging::Formatter)

              Datadog.logger.error(
                'Lograge and ActiveSupport::TaggedLogging (the default Rails log formatter) are not compatible: ' \
                  'Lograge does not account for Rails log tags, creating polluted logs and breaking log formatting. ' \
                  'Traces and Logs correlation may not work. ' \
                  'Either: 1. Disable tagged logging in your Rails configuration ' \
                  '`config.logger = ActiveSupport::Logger.new(STDOUT); ' \
                  'config.active_job.logger = ActiveSupport::Logger.new(STDOUT)` ' \
                  'or 2. Use the `semantic_logger` gem instead of `lograge`.'
              )
            end

            ::Lograge::LogSubscribers::Base.include(Instrumentation)
          end
        end
      end
    end
  end
end
