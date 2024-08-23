# frozen_string_literal: true

require_relative 'event'

module Datadog
  module Core
    module Telemetry
      # === INTRENAL USAGE ONLY ===
      #
      # Logging interface for sending telemetry logs... so we can fix them.
      #
      # For developer using this module:
      # - MUST NOT provide any sensitive information (PII)
      # - SHOULD reduce the data cardinality for batching/aggregation
      #
      # Before using it, ask yourself:
      # - Do we need to know about this (ie. internal error or client error)?
      # - How severe/critical is this error? (ie. error, warning, fatal)
      # - What information needed to make it actionable?
      #
      module Logging
        extend self

        # Extract datadog stack trace from the exception
        module DatadogStackTrace
          # Typically, `lib` is under `#{gem_name}-#{version}/`
          # but not the case when providing a bundler custom path in `Gemfile`
          REGEX = %r{/lib/datadog/}.freeze

          def self.from(exception)
            backtrace = exception.backtrace

            return unless backtrace
            return if backtrace.empty?

            stack_trace = +''
            backtrace.each do |line|
              stack_trace << if line.match?(REGEX)
                               # Removing host related information
                               line.sub(/^.*?(#{REGEX})/o, '\1') << ','
                             else
                               'REDACTED,'
                             end
            end

            stack_trace.chomp(',')
          end
        end

        def report(exception, level:, description: nil)
          # Annoymous exceptions to be logged as <Class:0x00007f8b1c0b3b40>
          message = +''
          message << (exception.class.name || exception.class.inspect)
          message << ':' << description if description

          event = Event::Log.new(
            message: message,
            level: level,
            stack_trace: DatadogStackTrace.from(exception)
          )

          dispatch(event)
        end

        def error(description)
          event = Event::Log.new(message: description, level: :error)

          dispatch(event)
        end

        private

        def dispatch(event)
          if (telemetry = Datadog.send(:components).telemetry)
            telemetry.log!(event)
          else
            Datadog.logger.debug { 'Attempting to send telemetry log when telemetry component is not ready' }
          end
        end
      end
    end
  end
end
