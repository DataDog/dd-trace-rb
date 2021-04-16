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
        when Exception then from_exception(value.class, value.message, full_backtrace(value))
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
          ex.backtrace.join("\n")
        end
      elsif Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.6.0')
        # Backports Ruby >= 2.6 output to older versions.
        # This exposes the 'cause' chain in the stack trace,
        # allowing for complete visibility of the error stack.
        def full_backtrace(ex)
          backtrace = []
          backtrace_for(ex, backtrace)

          # Avoid circular causes
          causes = Set.new
          causes.add(ex)

          while (cause = ex.cause) && !causes.include?(cause)
            backtrace_for(cause, backtrace)
            causes.add(cause)
          end

          backtrace.join("\n")
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

          error_line, *caller_lines = trace

          if error_line
            # Add Exception information to error line
            error_line = "#{error_line}: #{ex.message} (#{ex.class})"
            backtrace << error_line
          end

          if caller_lines
            # Ident stack trace for caller lines, to separate
            # them from the main error lines.
            caller_lines = caller_lines.map do |line|
              "	from #{line}"
            end

            backtrace.concat(caller_lines)
          end
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
      backtrace = Array(backtrace).join("\n")

      @type = Utils.utf8_encode(type)
      @message = Utils.utf8_encode(message)
      @backtrace = Utils.utf8_encode(backtrace)
    end

    # Optimized version for Exception objects.
    #
    # Exceptions return UTF-8 strings for their class name
    # and backtrace, or return an ASCII strings that is byte
    # equivalent to its UTF-8 counterpart:
    # `str.encode('ASCII').bytes == str.encode('UTF-8').bytes`
    def self.from_exception(clazz, message, backtrace)
      new(clazz, Utils.utf8_encode(message), backtrace)
    end

    BlankError = Error.new
    ContainsMessage = ->(v) { v.respond_to?(:message) }
  end
end
