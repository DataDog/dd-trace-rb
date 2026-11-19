# frozen_string_literal: true

require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      module DelayedJob
        # Patcher enables patching of 'delayed_job' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "plugin"
            add_instrumentation(::Delayed::Worker)
            patch_server_internals
          end

          def self.add_instrumentation(klass)
            klass.plugins << Plugin
          end

          def self.patch_server_internals
            require_relative "server_internal_tracer/worker"
            ::Delayed::Worker.prepend(ServerInternalTracer::Worker)
          end
        end
      end
    end
  end
end
