require_relative 'sequence'

module Datadog
  module Core
    module Utils
      # Acts as a unique dictionary of objects
      class ObjectSet
        # You can provide a block that defines how the key
        # for this message type is resolved.
        def initialize(seed = 0, &block)
          @sequence = Sequence.new(seed)
          @items = {}
          @key_block = block
        end

        # Submit an array of arguments that define the message.
        # If they match an existing message, it will return the
        # matching object. If it doesn't match, it will yield to
        # the block with the next ID & args given.
        def fetch(*args)
          # TODO: Array hashing is **really** expensive, we probably want to get rid of it in the future
          key = @key_block ? @key_block.call(*args) : args.hash
          @items[key] ||= yield(@sequence.next, *args)
        end

        def length
          @items.length
        end

        def objects
          @items.values
        end

        def freeze
          super
          @items.freeze
        end
      end
    end
  end
end
