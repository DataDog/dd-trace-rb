require_relative 'sequence'

module Datadog
  module Core
    module Utils
      # Tracks strings and returns IDs
      class StringTable
        def initialize
          @sequence = Sequence.new
          @ids = { ''.freeze => @sequence.next }
        end

        # Returns an ID for the string
        def fetch(string)
          @ids[string.to_s] ||= @sequence.next
        end

        # Returns the canonical copy of this string
        # Typically used for psuedo interning; reduce
        # identical copies of a string to one object.
        def fetch_string(string)
          return nil if string.nil?

          # Co-erce to string
          string = string.to_s

          # Add to string table if no match
          @ids[string] = @sequence.next unless @ids.key?(string)

          # Get and return matching string in table
          # NOTE: Have to resolve the key and retrieve from table again
          #       because "string" argument is not same object as string key.
          id = @ids[string]
          @ids.key(id)
        end

        def [](id)
          @ids.key(id)
        end

        def strings
          @ids.keys
        end
      end
    end
  end
end
