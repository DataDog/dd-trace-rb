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

        def target_version
          Integration.version
        end

        def patch
          require_relative 'resque_job'
          get_option(:workers).each { |worker| worker.extend(ResqueJob) }
        end

        def get_option(option)
          Datadog.configuration[:resque].get_option(option)
        end
      end
    end
  end
end
