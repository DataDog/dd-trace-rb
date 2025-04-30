# frozen_string_literal: true

require_relative 'core/deprecations'
require_relative 'core/extensions'

# We must load core extensions to make certain global APIs
# accessible: both for Datadog features and the core itself.
module Datadog
  # Common, lower level, internal code used (or usable) by two or more
  # products. It is a dependency of each product. Contrast with Datadog::Kit
  # for higher-level features.
  module Core
    extend Core::Deprecations
  end

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
