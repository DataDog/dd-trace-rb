# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      module FNV
        # FNV-1a 64-bit hash function.
        # @see https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function#FNV-1a_hash Algorithm
        # @see https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function#FNV_hash_parameters Prime and Offset Basis
        def self.fnv1_64(data)
          fnv_offset_basis = 14695981039346656037
          fnv_prime = 1099511628211

          hash_value = fnv_offset_basis
          data.each_byte do |byte|
            hash_value ^= byte
            hash_value = (hash_value * fnv_prime) & 0xFFFFFFFFFFFFFFFF
          end
          hash_value
        end
      end
    end
  end
end
