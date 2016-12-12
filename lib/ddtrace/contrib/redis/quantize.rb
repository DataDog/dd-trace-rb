module Datadog
  module Contrib
    module Redis
      # Quantize contains Redis-specific resource quantization tools.
      module Quantize
        PLACEHOLDER = '?'.freeze
        TOO_LONG_MARK = '...'.freeze
        VALUE_MAX_LEN = 100
        CMD_MAX_LEN = 1000

        module_function

        def format_arg(arg)
          a = arg.to_s
          a = a[0..(VALUE_MAX_LEN - TOO_LONG_MARK.length - 1)] + TOO_LONG_MARK if a.length > VALUE_MAX_LEN
          a
        rescue StandardError => e
          Datadog::Tracer.log.debug("non formattable Redis arg #{a}: #{e}")
          PLACEHOLDER
        end

        def format_command_args(command_args)
          cmd = command_args.map { |x| format_arg(x) }.join(' ')
          cmd = cmd[0..(CMD_MAX_LEN - TOO_LONG_MARK.length - 1)] + TOO_LONG_MARK if cmd.length > CMD_MAX_LEN
          cmd
        end
      end
    end
  end
end
