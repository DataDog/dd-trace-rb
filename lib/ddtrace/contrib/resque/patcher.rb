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
              get_option(:workers).each { |worker| worker.extend(ResqueJob) }
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
