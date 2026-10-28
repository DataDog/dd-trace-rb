# frozen_string_literal: true

require_relative "../tie"

module Datadog
  module Core
    module Remote
      module Tie
        # Extend Remote Configuration abilities with Tracing
        module Tracing
          # Tag per-request Remote Configuration metadata using Tracing
          def self.tag(boot, span)
            return if boot.nil?
            return if span.nil?

            # Hoisted so the nil guard narrows the component for the calls below.
            remote = Datadog::Core::Remote.active_remote
            return if remote.nil?

            # TODO: this is not thread-consistent
            ready = remote.healthy
            status = ready ? "ready" : "disconnected"

            span.set_tag("_dd.rc.client_id", remote.client.id)
            span.set_tag("_dd.rc.status", status)

            if boot.barrier != :pass
              span.set_tag("_dd.rc.boot.time", boot.time)

              if boot.barrier == :timeout
                span.set_tag("_dd.rc.boot.timeout", true)
              else
                span.set_tag("_dd.rc.boot.ready", ready)
              end
            end
          end
        end
      end
    end
  end
end
