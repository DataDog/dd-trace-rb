# frozen_string_literal: true

module Datadog
  module Core
    module Chunker
      module_function

      # An exception can occur if a single element is too large. That single
      # element will be returned in its own chunk. You have to verify by yourself
      # when such elements are returned.
      def chunk_by_size(list, max_chunk_size)
        chunk_agg = 0
        list.slice_before do |elem|
          size = elem.size
          chunk_agg += size
          if chunk_agg > max_chunk_size
            chunk_agg = size
            true
          else
            false
          end
        end
      end
    end
  end
end
