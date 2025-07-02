# frozen_string_literal: true

module Datadog
  # Lambda module streamlines instrumenting AWS Lambda functions with Datadog.
  module Lambda
    def self.configure_apm
      # Load tracing
      require_relative 'tracing'
      require_relative 'tracing/contrib'

      # Load other products (must follow tracing)
      require_relative 'profiling'
      require_relative 'appsec'
      require_relative 'di'
      require_relative 'error_tracking'
      require_relative 'kit'

      require_relative 'tracing/transport/io'

      # Needed to keep trace flushes on a single line
      $stdout.sync = true

      Datadog.configure do |c|
        # unless Datadog::Utils.extension_running?
        #   c.tracing.writer = Datadog::Tracing::SyncWriter.new(
        #     transport: Datadog::Tracing::Transport::IO.default
        #   )
        # end
        c.tags = { "_dd.origin": 'lambda' }
        # Enable AWS SDK instrumentation
        # c.tracing.instrument :aws if trace_managed_services?

        yield(c) if block_given?
      end
    end

    def self.trace_managed_services?
      dd_trace_managed_services = ENV['DD_TRACE_MANAGED_SERVICES']
      return true if dd_trace_managed_services.nil?

      dd_trace_managed_services.downcase == 'true'
    end
  end
end
