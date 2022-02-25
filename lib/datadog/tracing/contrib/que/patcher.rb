# frozen_string_literal: true
# typed: false

require 'datadog/tracing/contrib/que/integration'
require 'datadog/tracing/contrib/que/tracer'

module Datadog
  module Tracing
    module Contrib
      module Que
        # Patcher enables patching of 'que' module.
        module Patcher
          include Contrib::Patcher

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
end
