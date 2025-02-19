# frozen_string_literal: true

module Datadog
  module Tracing
    module Metadata
      # Adds complex structures tagging behavior through metastruct
      class Metastruct
        def initialize(metastruct = nil)
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
          merger = proc do |_, v1, v2|
            if v1.is_a?(Hash) && v2.is_a?(Hash)
              v1.merge(v2, &merger)
            elsif v1.is_a?(Array) && v2.is_a?(Array)
              v1.concat(v2)
            elsif v2.nil?
              v1
            else
              v2
            end
          end
          metastruct.merge!(second.to_h, &merger) # steep:ignore BlockTypeMismatch
        end

        def [](key)
          metastruct[key]
        end

        def []=(key, value)
          metastruct[key] = value
        end

        def dig(*keys)
          metastruct.dig(*keys)
        end

        def pretty_print(q)
          q.seplist metastruct.each do |key, value|
            q.text "#{key} => #{value}\n"
          end
        end

        def to_h
          metastruct.to_h
        end

        def to_msgpack(packer = nil)
          packer ||= MessagePack::Packer.new

          packer.write(metastruct.transform_values(&:to_msgpack))
        end

        private

        def metastruct
          @metastruct ||= {}
        end
      end
    end
  end
end
