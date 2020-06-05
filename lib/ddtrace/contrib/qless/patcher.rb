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

          workers_to_instrument = get_option(:workers)
          if workers_to_instrument.empty?
            # Instrument all Qless Workers
            ::Qless::Workers::BaseWorker.class_eval do
              # These are executed in inverse order of listing here
              include TracerCleaner
              include QlessJob
            end
          else
            # Instrument only select Qless Workers
            workers_to_instrument.each do |worker|
              worker.extend(::Qless::Job::SupportsMiddleware)
              worker.extend(TracerCleaner)
              worker.extend(QlessJob)
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:qless].get_option(option)
        end
      end
    end
  end
end
