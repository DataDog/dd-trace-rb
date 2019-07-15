module Datadog
  module Contrib
    module Redis
      # Quantize contains Redis-specific resource quantization tools.
      module Quantize
        PLACEHOLDER = '?'.freeze
        TOO_LONG_MARK = '...'.freeze
        VALUE_MAX_LEN = 50
        CMD_MAX_LEN = 500

        module_function

        def format_arg(arg)
          str = arg.is_a?(Symbol) ? arg.to_s.upcase : arg.to_s
          str = Utils.utf8_encode(str, binary: true, placeholder: PLACEHOLDER)
          Utils.truncate(str, VALUE_MAX_LEN, TOO_LONG_MARK)
        rescue => e
          Datadog::Tracer.log.debug("non formattable Redis arg #{str}: #{e}")
          PLACEHOLDER
        end

        def format_command_args(command_args)
          return 'AUTH ?' if auth_command?(command_args)
          cmd = command_args.map { |x| format_arg(x) }.join(' ')
          Utils.truncate(cmd, CMD_MAX_LEN, TOO_LONG_MARK)
        end

        def auth_command?(command_args)
          return false unless command_args.is_a?(Array) && !command_args.empty?
          command_args.first.to_sym == :auth
        end
      end
    end
  end
end
