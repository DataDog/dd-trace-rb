# frozen_string_literal: true

require_relative "tracer"

module Datadog
  module Tracing
    module Contrib
      module Que
        # Patcher enables patching of 'que' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            ::Que.job_middleware.push(Que::Tracer.new)
          end
        end
      end
    end
  end
end
