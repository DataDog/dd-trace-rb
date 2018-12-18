require 'set'
require 'ddtrace/patcher'

module Datadog
  # Shorthands for wrapping methods
  module MethodWrapping
    include Datadog::Patcher

    def wrapped_methods
      @wrapped_methods ||= Set.new
    end

    # Adds method block directly to the object.
    # Block is evaluated in the context of the object.
    # Faster than #wrap_method!
    def override_method!(method_name, &block)
      return unless block_given?

      without_warnings do
        define_singleton_method(method_name, &block).tap do
          wrapped_methods.add(method_name)
        end
      end
    end

    # Adds method wrapper to the object.
    # Block is evaluated in the original context of the block.
    # Slower than #override_method!
    def wrap_method!(original_method, &block)
      return unless block_given?
      original_method = original_method.is_a?(Symbol) ? method(original_method) : original_method

      override_method!(original_method.name) do |*original_args, &original_block|
        block.call(original_method, *original_args, &original_block)
      end
    end
  end
end
