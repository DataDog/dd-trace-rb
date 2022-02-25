# typed: false

require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/resque/integration'
require 'datadog/tracing/contrib/sidekiq/ext'

module Datadog
  module Tracing
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
          end
        end
      end
    end
  end
end
