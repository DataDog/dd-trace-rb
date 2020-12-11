require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module Qless
      # Patcher enables patching of 'qless' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require_relative 'qless_job'
          require_relative 'tracer_cleaner'

          # Instrument all Qless Workers
          ::Qless::Workers::BaseWorker.class_eval do
            # These are executed in inverse order of listing here
            include QlessJob
            include TracerCleaner
          end
        end

        def get_option(option)
          Datadog.configuration[:qless].get_option(option)
        end
      end
    end
  end
end
