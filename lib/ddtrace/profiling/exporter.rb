require 'ddtrace/profiling/transport/io/client'

module Datadog
  module Profiling
    # Writes profiling data to transport
    class Exporter
      attr_reader \
        :transport

      def initialize(transport)
        unless transport.is_a?(Profiling::Transport::Client)
          raise ArgumentError, 'Unsupported transport for profiling exporter.'
        end

        @transport = transport
      end

      def export(flush)
        transport.send_profiling_flush(flush)
      end
    end
  end
end
