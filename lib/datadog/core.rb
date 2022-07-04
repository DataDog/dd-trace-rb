# typed: strict

# TODO: Move these requires to smaller modules.
#       Would be better to lazy load these; not
#       all of these components will be used in
#       every application.
# require_relative 'core/buffer/cruby'
# require_relative 'core/buffer/random'
# require_relative 'core/buffer/thread_safe'
# require_relative 'core/chunker'
# require_relative 'core/configuration'
# require_relative 'core/diagnostics/environment_logger'
# require_relative 'core/diagnostics/ext'
# require_relative 'core/diagnostics/health'
# require_relative 'core/encoding'
# require_relative 'core/environment/cgroup'
# require_relative 'core/environment/class_count'
# require_relative 'core/environment/container'
# require_relative 'core/environment/ext'
# require_relative 'core/environment/gc'
# require_relative 'core/environment/identity'
# require_relative 'core/environment/socket'
# require_relative 'core/environment/thread_count'
# require_relative 'core/environment/variable_helpers'
# require_relative 'core/environment/vm_cache'
# require_relative 'core/error'
# require_relative 'core/event'
# require_relative 'core/git/ext'
# require_relative 'core/logger'
# require_relative 'core/metrics/client'
# require_relative 'core/metrics/ext'
# require_relative 'core/metrics/helpers'
# require_relative 'core/metrics/logging'
# require_relative 'core/metrics/metric'
# require_relative 'core/metrics/options'
# require_relative 'core/pin'
# require_relative 'core/quantization/hash'
# require_relative 'core/quantization/http'
# require_relative 'core/runtime/ext'
# require_relative 'core/runtime/metrics'
# require_relative 'core/utils'
# require_relative 'core/utils/compression'
# require_relative 'core/utils/database'
# require_relative 'core/utils/forking'
# require_relative 'core/utils/object_set'
# require_relative 'core/utils/only_once'
# require_relative 'core/utils/sequence'
# require_relative 'core/utils/string_table'
# require_relative 'core/utils/time'
# require_relative 'core/worker'
# require_relative 'core/workers/async'
# require_relative 'core/workers/interval_loop'
# require_relative 'core/workers/polling'
# require_relative 'core/workers/queue'
# require_relative 'core/workers/runtime_metrics'

require_relative 'core/extensions'

# We must load core extensions to make certain global APIs
# accessible: both for Datadog features and the core itself.
module Datadog
  # Common, lower level, internal code used (or usable) by two or more
  # products. It is a dependency of each product. Contrast with Datadog::Kit
  # for higher-level features.
  module Core
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
