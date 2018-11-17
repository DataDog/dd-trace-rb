module Datadog
  # Contains implementations for and provides a runtime-agnostic abstraction
  # of Ruby runtime tracing.
  module Runtime
    class << self
      attr_accessor :current
    end

    ruby_engine = defined?(RUBY_ENGINE) && RUBY_ENGINE

    if ruby_engine == 'ruby'
      require 'ddtrace/runtime/mri'
      self.current = MRI
    end
  end
end
