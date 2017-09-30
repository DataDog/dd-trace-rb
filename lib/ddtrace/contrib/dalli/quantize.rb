module Datadog
  module Contrib
    module Dalli
      # Quantize contains dalli-specic quantization tools.
      module Quantize
        MAX_CMD_LENGTH = 100

        module_function

        def format_command(operation, args)
          command = [operation, *args].join(' ').strip
          Utils.truncate(command, MAX_CMD_LENGTH)
        end
      end
    end
  end
end
