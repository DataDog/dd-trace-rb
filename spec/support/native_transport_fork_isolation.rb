# frozen_string_literal: true

# Test isolation for the native trace-exporter specs.
#
# `Datadog::Tracing::Transport::Native::Transport#initialize` registers
# process-global `AtForkMonkeyPatch` hooks (`:before`/`:parent`/`:child`) whose
# closures capture the native exporter. Those hooks are never deregistered, so
# the exporter -- and the long-lived Rust/tokio runtime threads it owns -- stays
# reachable (and alive) for the rest of the process, even after the transport is
# dropped and `GC.start` runs.
#
# Several native specs spawn a mock agent with `fork`. When such a fork happens
# while a leaked exporter from an earlier example group is still alive, the
# forked child inherits the exporter object but NOT the runtime's worker threads
# (only the forking thread survives a `fork`). Freeing that half-dead runtime
# when the child exits then deadlocks inside libdatadog, so the child never
# terminates and the parent's `Process.wait` hangs. This manifests as a
# multi-minute, seed-dependent hang in the combined native spec suite.
#
# `fork_spec.rb` already protects itself by snapshotting and clearing the global
# registry around its own groups. This support module generalizes that idea to
# every native-transport example group: it snapshots the registry before each
# group, restores it afterwards (dropping any hooks the group registered), and
# runs `GC.start` so that an exporter kept alive only by those now-removed hooks
# is collected in the PARENT process -- where its runtime can shut down cleanly
# -- before the next group forks.
module NativeTransportForkIsolation
  STAGES = {
    before: :AT_FORK_BEFORE_BLOCKS,
    parent: :AT_FORK_PARENT_BLOCKS,
    child: :AT_FORK_CHILD_BLOCKS,
  }.freeze

  module_function

  def registry
    require 'datadog/core/utils/at_fork_monkey_patch'
    Datadog::Core::Utils::AtForkMonkeyPatch
  end

  def push_snapshot
    snapshot = STAGES.each_with_object({}) do |(stage, const), saved|
      saved[stage] = registry.const_get(const).dup
    end
    stack << snapshot
  end

  def pop_and_restore
    snapshot = stack.pop
    return unless snapshot

    STAGES.each do |stage, const|
      registry.const_get(const).replace(snapshot[stage])
    end
  end

  def stack
    Thread.current[:native_transport_fork_isolation_stack] ||= []
  end
end

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/datadog/tracing/transport/native/}) do |metadata|
    metadata[:native_transport_fork_isolation] = true
  end

  config.prepend_before(:context, :native_transport_fork_isolation) do
    NativeTransportForkIsolation.push_snapshot
  end

  config.append_after(:context, :native_transport_fork_isolation) do
    NativeTransportForkIsolation.pop_and_restore
    # Free any exporter that was kept alive only by the hooks we just removed,
    # so its runtime shuts down here in the parent rather than being inherited
    # (broken) by a later fork.
    GC.start
  end
end
