# typed: true

require 'datadog/tracing'
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/qless/integration'

module Datadog
  module Tracing
    module Contrib
      module Qless
        # Patcher enables patching of 'qless' module.
        module Patcher
          include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require_relative 'qless_job'
            require_relative 'tracer_cleaner'

            # Instrument all Qless Workers
            # These are executed in inverse order of listing here
            ::Qless::Workers::BaseWorker.include(QlessJob)
            ::Qless::Workers::BaseWorker.include(TracerCleaner)
          end

          def get_option(option)
            Datadog.configuration[:qless].get_option(option)
          end
        end
      end
    end
  end
end
