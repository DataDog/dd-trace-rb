require 'datadog/tracing/span'
require 'datadog/tracing/distributed/helpers'
          
module Datadog
  module Tracing
    module Distributed
      class MetadataParser

        def initialize(metadata)
          @metadata = metadata
        end

        def id(key, base = 10)
          Helpers.value_to_id(metadata_for_key(key), base)
        end


        def number(key, base = 10)
          Helpers.value_to_number(metadata_for_key(key), base)
        end

        def metadata_for_key(key)
          # metadata values can be arrays (multiple headers with the same key)
          value = @metadata[key]
          if value.is_a?(Array)
            value.first
          else
            value
          end
        end
      end
    end
  end
end
