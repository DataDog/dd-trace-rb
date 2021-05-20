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

          ::Resque::Job.prepend(Resque::Job)

          workers = Datadog.configuration[:resque][:workers] || []
          workers.each { |worker| worker.extend(ResqueJob) }
        end
      end
    end
  end
end
