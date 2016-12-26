# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module Elasticsearch
      # Patcher enables patching of 'elasticsearch/transport' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          if !@patched && (defined?(::Elasticsearch::Transport::VERSION) && \
                           Gem::Version.new(::Elasticsearch::Transport::VERSION) >= Gem::Version.new('1.0.0'))
            begin
              require 'ddtrace/contrib/elasticsearch/core'
              ::Elasticsearch::Transport::Client.prepend Datadog::Contrib::Elasticsearch::TracedClient
              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Elastic Search integration: #{e}")
            end
          end
          @patched
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
