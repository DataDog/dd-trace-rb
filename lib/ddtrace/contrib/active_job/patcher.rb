# typed: true
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_job/ext'
require 'ddtrace/contrib/active_job/events'

module Datadog
  module Contrib
    module ActiveJob
      # Patcher enables patching of 'active_job' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          Events.subscribe!
        end
      end
    end
  end
end
