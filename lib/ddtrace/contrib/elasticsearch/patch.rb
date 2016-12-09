module Datadog
  module Contrib
    module Elasticsearch
      # Patch enables patching of 'elasticsearch/transport' module.
      module Patch
        @patched = false

        module_function

        def patched?
          @patched
        end

        def patch
          if !@patched && (defined?(::Elasticsearch::Transport::VERSION) && \
                                  Gem::Version.new(::Elasticsearch::Transport::VERSION) >= Gem::Version.new('1.0.0'))
            require 'ddtrace/contrib/elasticsearch/core'
            @patched = true
          end
        end
      end
    end
  end
end
