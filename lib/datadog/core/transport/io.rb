# typed: true
require 'datadog/core/encoding'
require 'datadog/core/transport/io/client'
require 'datadog/core/transport/io/traces'

module Datadog
  module Core
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
            options.fetch(:out, $stdout),
            options.fetch(:encoder, Core::Encoding::JSONEncoder)
          )
        end
      end
    end
  end
end
