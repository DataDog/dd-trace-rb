module Datadog
  # Represents an wrapped method, with a reference to the original block
  # and the block that wraps around it.
  class MethodWrapper
    attr_reader \
      :original,
      :wrapper

    DEFAULT_WRAPPER = proc { |original, *args, &block| original.call(*args, &block) }

    def initialize(original, &block)
      @original = original
      @wrapper = block_given? ? block : DEFAULT_WRAPPER
    end

    def call(*args, &block)
      wrapper.call(original, *args, &block)
    end
  end
end
