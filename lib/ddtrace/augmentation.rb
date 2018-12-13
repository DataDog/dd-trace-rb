require 'ddtrace/augmentation/method_wrapper'
require 'ddtrace/augmentation/method_wrapping'
require 'ddtrace/augmentation/shim'

module Datadog
  # Namespace for components that help modify
  # existing code for instrumentation purposes.
  module Augmentation
    def shim(object, &block)
      Shim.new(object, &block)
    end
  end
end
