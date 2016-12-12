module Datadog
  module Contrib
    module Redis
      # Quantize contains Redis-specific resource quantization tools.
      module Quantize
        module_function

        def format_command_args(command_args)
          # TODO(christian): stringify & trim
          command_args.join(' ')
        end
      end
    end
  end
end
