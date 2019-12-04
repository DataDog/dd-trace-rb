require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sidekiq/ext'

module Datadog
  module Contrib
    module Resque
      # Patcher enables patching of 'resque' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:resque)
        end

        def patch
          do_once(:resque) do
            begin
              require_relative 'enqueue'
              require_relative 'job'
              require_relative 'worker'

              # Patch Resque class
              ::Resque.class_eval { prepend Enqueue }
              # Patch Resque::Job class
              ::Resque::Job.class_eval { prepend Job }
              # Patch Resque::Worker class
              ::Resque::Worker.class_eval { prepend Worker }

              # Setup pin on Resque
              Datadog::Pin.new(
                get_option(:service_name),
                tracer: get_option(:tracer)
              ).onto(::Resque)
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Resque integration: #{e}")
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:resque].get_option(option)
        end
      end
    end
  end
end
