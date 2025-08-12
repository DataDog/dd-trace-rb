# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      # A module for coercing arbitrary objects into hashes.
      module HashCoercion
        # A best effort to coerce an object to a hash with methods known to various
        # frameworks with a fallback to standard library.
        #
        # @param object [Object] The object to coerce.
        # @return [Hash, nil] The coerced `Hash` or `nil` if the object is not coercible.
        def self.coerce(object)
          return object.as_json if object.respond_to?(:as_json)
          return object.to_hash if object.respond_to?(:to_hash)
          return object.to_h if object.respond_to?(:to_h)

          nil
        end
      end
    end
  end
end
