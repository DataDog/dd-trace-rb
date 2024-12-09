# frozen_string_literal: true

require_relative 'event'

require 'pathname'

module Datadog
  module Core
    module Telemetry
      # === INTERNAL USAGE ONLY ===
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
        # Extract datadog stack trace from the exception
        module DatadogStackTrace
          GEM_ROOT = Pathname.new("#{__dir__}/../../../..").cleanpath.to_s

          def self.from(exception)
            backtrace = exception.backtrace

            return unless backtrace
            return if backtrace.empty?

            # vendored deps
            vendored_deps = Gem.path.any? { |p| p.start_with?(GEM_ROOT) }

            backtrace.map do |line|
              if !vendored_deps && line.start_with?(GEM_ROOT) ||
                  vendored_deps && line.start_with?(GEM_ROOT) && Gem.path.none? { |p| line.start_with?(p) }
                line[GEM_ROOT.length..-1] || ''
              else
                'REDACTED'
              end
            end.join(',')
          end
        end

        def report(exception, level: :error, description: nil)
          # Annoymous exceptions to be logged as <Class:0x00007f8b1c0b3b40>
          message = +''
          message << (exception.class.name || exception.class.inspect)
          message << ':' << description if description

          event = Event::Log.new(
            message: message,
            level: level,
            stack_trace: DatadogStackTrace.from(exception)
          )

          log!(event)
        end

        def error(description)
          event = Event::Log.new(message: description, level: :error)

          log!(event)
        end
      end
    end
  end
end
