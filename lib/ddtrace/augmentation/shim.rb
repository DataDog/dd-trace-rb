require 'set'
require 'ddtrace/patcher'
require 'ddtrace/augmentation/method_wrapping'

module Datadog
  # A "stand-in" that intercepts calls to another object. i.e. man-in-the-middle.
  # This shim forwards all methods to object, except those overriden.
  # Useful if you want to intercept inbound behavior to an object without modifying
  # the object in question, especially useful if the overridding behavior shouldn't be global.
  class Shim
    extend Forwardable
    include Datadog::Patcher
    include Datadog::MethodWrapping

    METHODS = Set[
      :override_method!,
      :shim,
      :shim?,
      :shim_target,
      :wrap_method!,
      :wrapped_methods
    ].freeze

    EXCLUDED_METHODS = Set[
      # For all objects
      :__binding__,
      :__id__,
      :__send__,
      :extend,
      :itself,
      :object_id,
      :respond_to?,
      :tap
    ].freeze

    attr_reader :shim_target, :shim

    def self.shim?(object)
      # Check whether it responds to #shim? because otherwise the
      # Shim forwards all method calls, including type checks to
      # the wrapped object, to mimimize its intrusion.
      object.respond_to?(:shim?)
    end

    # Pass this a block to override methods
    def initialize(shim_target)
      @shim = self
      @shim_target = shim_target

      # Save a reference to the original :define_singleton_method
      # so methods can be defined on the shim after forwarding is applied.
      @definition_method = method(:define_singleton_method)

      # Wrap any methods
      yield(self) if block_given?

      # Forward methods
      forwarded_methods = (
        shim_target.public_methods.to_set \
        - METHODS \
        - EXCLUDED_METHODS \
        - wrapped_methods
      )
      forward_methods!(*forwarded_methods)
    end

    def override_method!(method_name, &block)
      return unless block_given?

      without_warnings do
        @definition_method.call(method_name, &block).tap do
          wrapped_methods.add(method_name)
        end
      end
    end

    def wrap_method!(method_name, &block)
      super(shim_target.method(method_name), &block)
    end

    def shim?
      true
    end

    def respond_to?(method_name)
      return true if METHODS.include?(method_name)
      shim_target.respond_to?(method_name)
    end

    private

    def forward_methods!(*forwarded_methods)
      return if forwarded_methods.empty?

      singleton_class.send(
        :def_delegators,
        :@shim_target,
        *forwarded_methods
      )
    end
  end
end
