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
        def fetch(*args)
          key = @key_block ? @key_block.call(*args) : args.hash
          @items[key] ||= yield(@sequence.next, *args)
        end

        def messages
          @items.values
        end
      end
    end
  end
end
