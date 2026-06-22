# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      module HTTP
        module BodyReader
          module_function

          def read(body, limit:, rewind_before_read: false)
            return body.byteslice(0, limit + 1) if body.is_a?(String)
            return if body.nil? || !body.respond_to?(:read)
            return if rewind_before_read && !body.respond_to?(:rewind)

            rewound = false

            if rewind_before_read
              return unless rewind(body)
              rewound = true
            end

            buffer = +''.b
            max = limit + 1

            while buffer.bytesize <= limit
              chunk = body.read(max - buffer.bytesize)
              break if chunk.nil? || chunk.empty?

              buffer << chunk
            end

            buffer
          rescue => e
            Datadog.logger.debug { "AppSec: Failed to read body: #{e.class}: #{e.message}" }

            raise
          ensure
            rewind(body) if rewound
          end

          private_class_method def rewind(body)
            body.rewind
            true
          rescue => e
            Datadog.logger.debug { "AppSec: Failed to rewind body: #{e.class}: #{e.message}" }
            false
          end
        end
      end
    end
  end
end
