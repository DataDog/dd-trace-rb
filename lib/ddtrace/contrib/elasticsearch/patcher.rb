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
            require 'ddtrace/contrib/elasticsearch/core' # here, patching happens
            @patched = true
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
