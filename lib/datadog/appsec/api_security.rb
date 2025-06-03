# frozen_string_literal: true

require_relative 'api_security/sampler'

module Datadog
  module AppSec
    # A namespace for API Security features.
    module APISecurity
      def self.sample?(request, response)
        Sampler.thread_local.sample?(request, response)
      end

      def self.sample_trace?(trace)
        return true unless Datadog.configuration.apm.tracing.enabled

        Datadog.send(:components).tracer.sampler.sample!(trace)
      end
    end
  end
end
