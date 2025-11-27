# frozen_string_literal: true

require_relative 'core/deprecations'
require_relative 'core/configuration/config_helper'
require_relative 'core/extensions'

# We must load core extensions to make certain global APIs
# accessible: both for Datadog features and the core itself.
module Datadog
  # Common, lower level, internal code used (or usable) by two or more
  # products. It is a dependency of each product. Contrast with Datadog::Kit
  # for higher-level features.
  module Core
    extend Core::Deprecations

    LIBDATADOG_API_FAILURE =
      begin
        require "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}"
        nil
      rescue LoadError => e
        e.message
      end

    # Namespace for native extension related code
    module Native
      # Base error type for exceptions raised by our native extensions.
      # These errors have both the original error message and a telemetry-safe message.
      # The telemetry-safe message is statically defined and does not possess dynamic data.
      module Error
        attr_reader :telemetry_message

        def initialize(message, telemetry_message = nil)
          super(message)
          @telemetry_message = telemetry_message
        end
      end

      # Exception classes are defined by the libdatadog_api C extension
      # RuntimeError, ArgumentError, and TypeError will be populated at runtime
      # by Init_libdatadog_api in ext/libdatadog_api/init.c
    end

    # Prepend the Error module to the exception classes defined by the C extension
    if defined?(Native::RuntimeError)
      Native::RuntimeError.prepend(Native::Error)
      Native::ArgumentError.prepend(Native::Error)
      Native::TypeError.prepend(Native::Error)
    end

    # Backward compatibility aliases
    NativeError = Native::Error if defined?(Native::Error)
    NativeRuntimeError = Native::RuntimeError if defined?(Native::RuntimeError)
    NativeArgumentError = Native::ArgumentError if defined?(Native::ArgumentError)
    NativeTypeError = Native::TypeError if defined?(Native::TypeError)
  end

  DATADOG_ENV = Core::Configuration::ConfigHelper.new
  extend Core::Extensions

  # Add shutdown hook:
  # Ensures the Datadog components have a chance to gracefully
  # shut down and cleanup before terminating the process.
  at_exit do
    if Interrupt === $! # rubocop:disable Style/SpecialGlobalVars is process terminating due to a ctrl+c or similar?
      Datadog.send(:handle_interrupt_shutdown!)
    else
      Datadog.shutdown!
    end
  end
end
