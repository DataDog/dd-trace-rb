require 'ddtrace/utils/sequence'

module Datadog
  module Profiling
    module Pprof
      # Acts as a unique dictionary of protobuf messages
      class MessageSet
        # You can provide a block that defines how the key
        # for this message type is resolved.
        def initialize(seed = 0, &block)
          @sequence = Utils::Sequence.new(seed)
          @items = {}
          @key_block = block
        end

        # Submit an array of arguments that define the message.
        # If they match an existing message, it will return the
        # matching object. If it doesn't match, it will yield to
        # the block with the next ID & args given.
        def fetch(*args, &block)
          key = @key_block ? @key_block.call(*args) : args.hash
          # TODO: Ruby 2.0 doesn't like yielding here... switch when 2.0 is dropped.
          # rubocop:disable Performance/RedundantBlockCall
          @items[key] ||= block.call(@sequence.next, *args)
        end

        def length
          @items.length
        end

        def messages
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
