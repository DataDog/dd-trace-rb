# frozen_string_literal: true

require 'set'

# Datadog global namespace
module Datadog
  # Error is a value-object responsible for sanitizing/encapsulating error data
  class Error
    attr_reader :type, :message, :backtrace

    class << self
      def build_from(value)
        case value
        when Error then value
        when Array then new(*value)
        when Exception then new(value.class, value.message, full_backtrace(value))
        when ContainsMessage then new(value.class, value.message)
        else BlankError
        end
      end

      private

      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
        # Ruby 2.0 exceptions don't have `cause`.
        # Only current exception stack trace is reported.
        # This is the same behavior as before.
        def full_backtrace(ex)
          backtrace = ex.backtrace
          backtrace.join("\n") if backtrace
        end
      elsif Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.6.0')
        # Backports Ruby >= 2.6 output to older versions.
        # This exposes the 'cause' chain in the stack trace,
        # allowing for complete visibility of the error stack.
        def full_backtrace(ex)
          backtrace = String.new
          backtrace_for(ex, backtrace)

          # Avoid circular causes
          causes = Hash.new
          causes[ex] = true

          while (cause = ex.cause) && !causes.key?(cause)
            backtrace_for(cause, backtrace)
            causes[cause] = true
          end

          backtrace
        end

        # Outputs the following format for exceptions:
        #
        # ```
        # error_spec.rb:55:in `wrapper': wrapper layer (RuntimeError)
        # 	from error_spec.rb:40:in `wrapper'
        # 	from error_spec.rb:61:in `caller'
        #   ...
        # ```
        def backtrace_for(ex, backtrace)
          trace = ex.backtrace
          return unless trace

          if trace[0]
            # Add Exception information to error line
            backtrace << "#{trace[0]}: #{ex.message} (#{ex.class})"
          end

          if trace[1]
            # Ident stack trace for caller lines, to separate
            # them from the main error lines.
            trace[1..-1].each do |line|
              backtrace << "\n from "
              backtrace << line
            end
          end

          backtrace << "\n"
        end
      else # Ruby >= 2.6.0
        # Full stack trace, with each cause reported with its
        # respective stack trace.
        def full_backtrace(ex)
          ex.full_message(highlight: false, order: :top)
        end
      end
    end

    def initialize(type = nil, message = nil, backtrace = nil)
      backtrace = Array(backtrace).join("\n") unless backtrace.is_a?(String)

      @type = Utils.utf8_encode(type)
      @message = Utils.utf8_encode(message)
      @backtrace = Utils.utf8_encode(backtrace)
    end

    BlankError = Error.new
    ContainsMessage = ->(v) { v.respond_to?(:message) }
  end
end
