# typed: strict

# TODO: Move these requires to smaller modules.
#       Would be better to lazy load these; not
#       all of these components will be used in
#       every application.
# require 'datadog/core/buffer/cruby'
# require 'datadog/core/buffer/random'
# require 'datadog/core/buffer/thread_safe'
# require 'datadog/core/chunker'
# require 'datadog/core/configuration'
# require 'datadog/core/diagnostics/environment_logger'
# require 'datadog/core/diagnostics/ext'
# require 'datadog/core/diagnostics/health'
# require 'datadog/core/encoding'
# require 'datadog/core/environment/cgroup'
# require 'datadog/core/environment/class_count'
# require 'datadog/core/environment/container'
# require 'datadog/core/environment/ext'
# require 'datadog/core/environment/gc'
# require 'datadog/core/environment/identity'
# require 'datadog/core/environment/socket'
# require 'datadog/core/environment/thread_count'
# require 'datadog/core/environment/variable_helpers'
# require 'datadog/core/environment/vm_cache'
# require 'datadog/core/error'
# require 'datadog/core/event'
# require 'datadog/core/git/ext'
# require 'datadog/core/logger'
# require 'datadog/core/metrics/client'
# require 'datadog/core/metrics/ext'
# require 'datadog/core/metrics/helpers'
# require 'datadog/core/metrics/logging'
# require 'datadog/core/metrics/metric'
# require 'datadog/core/metrics/options'
# require 'datadog/core/pin'
# require 'datadog/core/quantization/hash'
# require 'datadog/core/quantization/http'
# require 'datadog/core/runtime/ext'
# require 'datadog/core/runtime/metrics'
# require 'datadog/core/utils'
# require 'datadog/core/utils/compression'
# require 'datadog/core/utils/database'
# require 'datadog/core/utils/forking'
# require 'datadog/core/utils/object_set'
# require 'datadog/core/utils/only_once'
# require 'datadog/core/utils/sequence'
# require 'datadog/core/utils/string_table'
# require 'datadog/core/utils/time'
# require 'datadog/core/worker'
# require 'datadog/core/workers/async'
# require 'datadog/core/workers/interval_loop'
# require 'datadog/core/workers/polling'
# require 'datadog/core/workers/queue'
# require 'datadog/core/workers/runtime_metrics'

require 'datadog/core/extensions'

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
