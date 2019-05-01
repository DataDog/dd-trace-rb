module Datadog
  # Namespace for ddtrace OpenTracing implementation
  module Runtime
    module_function

    def supported?
      RUBY_VERSION >= '1.9.3' || (defined?(JRUBY_VERSION) && JRUBY_VERSION >= '9.1.5')
    end
  end
end
