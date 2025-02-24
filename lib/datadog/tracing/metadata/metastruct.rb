# frozen_string_literal: true

require 'forwardable'

module Datadog
  module Tracing
    module Metadata
      # Adds complex structures tagging behavior through metastruct
      class Metastruct
        extend Forwardable

        MERGER = proc do |_, v1, v2|
          if v1.is_a?(Hash) && v2.is_a?(Hash)
            v1.merge(v2, &MERGER)
          elsif v1.is_a?(Array) && v2.is_a?(Array)
            v1.concat(v2)
          elsif v2.nil?
            v1
          else
            v2
          end
        end

        def self.empty
          new({})
        end

        def initialize(metastruct)
          @metastruct = metastruct
        end

        # Deep merge two metastructs
        # If the types are not both Arrays or Hashes, the second one will overwrite the first one
        #
        # Example with same types:
        # metastruct = { a: { b: [1, 2] } }
        # second = { a: { b: [3, 4], c: 5 } }
        # result = { a: { b: [1, 2, 3, 4], c: 5 } }
        #
        # Example with different types:
        # metastruct = { a: { b: 1 } }
        # second = { a: { b: [2, 3] } }
        # result = { a: { b: [2, 3] } }
        def deep_merge!(second)
          @metastruct.merge!(second.to_h, &MERGER)
        end

        def_delegators :@metastruct, :[], :[]=, :dig, :to_h

        def pretty_print(q)
          q.seplist @metastruct.each do |key, value|
            q.text "#{key} => #{value}\n"
          end
        end

        def to_msgpack(packer = nil)
          packer ||= MessagePack::Packer.new

          packer.write(@metastruct.transform_values(&:to_msgpack))
        end
      end
    end
  end
end
