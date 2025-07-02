# frozen_string_literal: true

require 'aws_lambda_ric/lambda_handler'

module Datadog
  # Lambda module streamlines instrumenting AWS Lambda functions with Datadog.
  module Lambda
    def self.handler(event:, context:)
      begin
        env_handler = ENV['DD_LAMBDA_HANDLER']
        raise 'DD_LAMBDA_HANDLER is not set, Datadog will not work as expected' if env_handler.nil?

        @lambda_handler = LambdaHandler.new(env_handler: env_handler)
        require @lambda_handler.handler_file_name

        configure_apm do |c|
          c.tracing.instrument :aws
        end

        @lambda_handler.call_handler(request: event, context: context)
      rescue Exception => e # rubocop:disable Lint/RescueException
        raise e
      end
    end

    def self.configure_apm
      require_relative 'datadog/tracing'
      require_relative 'datadog/tracing/transport/io'

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
        c.tracing.instrument :aws if trace_managed_services?

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
