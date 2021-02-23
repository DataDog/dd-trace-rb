require 'ddtrace/contrib/dalli/ext'

module Datadog
  module Contrib
    module Dalli
      # Quantize contains dalli-specic quantization tools.
      module Quantize
        module_function

        def format_command(operation, args)
          placeholder = "#{operation} BLOB (OMITTED)"
          command = [operation, *args].join(' ').strip
          command = Utils.utf8_encode(command, binary: true, placeholder: placeholder)
          Utils.truncate(command, Ext::QUANTIZE_MAX_CMD_LENGTH)
        rescue => e
          Datadog.logger.debug("Error sanitizing Dalli operation: #{e}")
          placeholder
        end
      end
    end
  end
end
