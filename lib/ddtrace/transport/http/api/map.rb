require_relative 'fallbacks'

module Datadog
  module Transport
    module HTTP
      module API
        # A mapping of API version => API Routes/Instance
        class Map < Hash
          include Fallbacks
        end
      end
    end
  end
end
