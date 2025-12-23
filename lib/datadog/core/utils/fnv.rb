# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      module FNV
        # FNV-1a 64-bit hash function.
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
