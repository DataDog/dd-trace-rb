# frozen_string_literal: true

module Datadog
  module Core
    # Chunks lists of Strings into batches by byte size.
    module Chunker
      # Chunks a list of Strings into batches whose element byte sizes add
      # up to at most +max_chunk_size+. An element larger than
      # +max_chunk_size+ forms its own chunk.
      #
      # @param list [Enumerable<String>] list of elements
      # @param max_chunk_size [Integer] maximum byte size of the elements of one chunk
      # @return [Enumerable<Array<String>>] lazy list of chunks
      def self.chunk_by_size(list, max_chunk_size)
        chunk_agg = 0
        list.slice_before do |elem|
          size = elem.bytesize
          chunk_agg += size
          if chunk_agg > max_chunk_size
            # Can't fit element in current chunk, start a new one.
            chunk_agg = size
            true
          else
            # Add to current chunk
            false
          end
        end
      end
    end
  end
end
