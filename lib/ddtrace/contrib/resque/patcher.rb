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
              require_relative 'resque_job'
              add_pin
              get_option(:workers).each { |worker| worker.extend(ResqueJob) }
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Resque integration: #{e}")
            end
          end
        end

        def add_pin
          Pin.new(
            get_option(:service_name),
            app: Ext::APP,
            app_type: Datadog::Ext::AppTypes::WORKER,
            tracer: get_option(:tracer)
          ).onto(::Resque)
        end

        def get_option(option)
          Datadog.configuration[:resque].get_option(option)
        end
      end
    end
  end
end
