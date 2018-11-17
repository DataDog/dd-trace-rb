module Datadog
  # Ruby runtime-specific functionality.
  module Runtime
    ruby_engine = defined?(RUBY_ENGINE) && RUBY_ENGINE

    if ruby_engine == 'ruby'
      require 'ddtrace/runtime/mri'
    end
  end
end
