# frozen_string_literal: true

require 'ddtrace/contrib/que/tracer'

module Datadog
  module Contrib
    module Que
      # Patcher enables patching of 'que' module.
      module Patcher
        include Datadog::Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          ::Que.job_middleware.push(Que::Tracer.new)
        end
      end
    end
  end
end
