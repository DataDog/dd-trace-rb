module Datadog
  module Transport
    module HTTP
      module API
        # An API configured with adapter and routes
        class Instance
          attr_reader \
            :adapter,
            :headers,
            :spec

          def initialize(spec, adapter, options = {})
            @spec = spec
            @adapter = adapter
            @headers = options.fetch(:headers, {})
          end

          def call(env)
            adapter.call(env)
          end
        end
      end
    end
  end
end
