require 'ddtrace/encoding'
require 'ddtrace/transport/io/client'
require 'ddtrace/transport/io/traces'

module Datadog
  module Transport
    # Namespace for IO transport components
    module IO
      module_function

      # Builds a new Transport::IO::Client
      def new(out, encoder)
        Client.new(out, encoder)
      end

      # Builds a new Transport::IO::Client with default settings
      # Pass options to override any settings.
      def default(options = {})
        new(
          options.fetch(:out, STDOUT),
          options.fetch(:encoder, Encoding::JSONEncoder)
        )
      end
    end
  end
end
