# frozen_string_literal: true

module Datadog
  module Core
    # A some-what abstract class representing a collection of headers.
    #
    # Use the `HeaderCollection.from_hash` function to create a header collection from a `Hash`.
    # Another option is to use `HashHeaderCollection` directly.
    class HeaderCollection
      # Gets a single value of the header with the given name, case insensitive.
      #
      # @returns [String, nil] A single value of the header, or nil if the header with
      #   the given name is missing from the collection.
      def get(header_name)
        nil
      end

      # This can be useful for testing or other trivial use cases.
      def self.from_hash(hash)
        HashHeaderCollection.new(hash)
      end
    end

    class HashHeaderCollection < HeaderCollection
      def initialize(hash)
        super()
        @hash = {}.tap do |res|
          hash.each_pair { |key, value| res[key.downcase] = value }
        end
      end

      def get(header_name)
        @hash[header_name.downcase]
      end
    end
  end
end
