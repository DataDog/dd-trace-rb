require 'ddtrace/profiling/transport/io/client'
require 'ddtrace/profiling/encoding/profile'

module Datadog
  module Profiling
    module Transport
      # Namespace for profiling IO transport components
      module IO
        module_function

        # Builds a new Profiling::Transport::IO::Client
        def new(out, encoder, options = {})
          Client.new(out, encoder, options)
        end

        # Builds a new Profiling::Transport::IO::Client with default settings
        # Pass options to override any settings.
        def default(options = {})
          options = options.dup

          new(
            options.delete(:out) || STDOUT,
            options.delete(:encoder) || Profiling::Encoding::Profile::Protobuf,
            options
          )
        end
      end
    end
  end
end
