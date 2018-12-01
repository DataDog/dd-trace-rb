module Datadog
  module Shim
    def self.double(object, &block)
      Double.new(object, &block)
    end

    module Wrapping
      def wrapped_methods
        @wrapped_methods ||= Set.new
      end

      # Adds method block directly to the object.
      # Block is evaluated in the context of the object.
      # Faster than #wrap_method!
      def inject_method!(name, &block)
        define_singleton_method(name, &block).tap do |r|
          wrapped_methods.add(name)
        end
      end

      # Adds method wrapper to the object.
      # Block is evaluated in the original context of the block.
      # Slower than #inject_method!
      def wrap_method!(name, &block)
        define_singleton_method(name) do |*original_args, &original_block|
          block.call(*original_args, &original_block)
        end.tap do |r|
          wrapped_methods.add(name)
        end
      end
    end

    class Double
      extend Forwardable
      include Shim::Wrapping

      EXCLUDED_METHODS = [
        :__binding__,
        :__id__,
        :__send__,
        :define_singleton_method,
        :extend,
        :forward_methods!,
        :itself,
        :object_id,
        :singleton_class,
        :tap,
        # From Shim::Wrapping
        :wrapped_methods,
        :inject_method!,
        :wrap_method!
      ].freeze

      attr_reader :shim_target, :shim

      def self.is_shim?(object)
        object.singleton_class.superclass <= self
      end

      def initialize(shim_target, &block)
        @shim = self
        @shim_target = shim_target

        # Wrap any methods
        block.call(self)

        # Forward methods
        forwarded_methods = shim_target.public_methods - EXCLUDED_METHODS - wrapped_methods.to_a
        forward_methods!(*forwarded_methods)
      end

      def forward_methods!(*forwarded_methods)
        return if forwarded_methods.empty?

        singleton_class.send(
          :def_delegators,
          :@shim_target,
          *forwarded_methods
        )
      end
    end

    class MethodWrapper
      attr_reader \
        :original,
        :wrapper

      DEFAULT_WRAPPER = Proc.new { |*args, &block| original.call(*args, &block) }

      def initialize(original, &block)
        @original = original
        @wrapper = block_given? ? block : DEFAULT_WRAPPER
      end

      def invoke(*args, &block)
        wrapper.call(original, *args, &block)
      end
    end
  end
end
