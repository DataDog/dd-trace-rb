# frozen_string_literal: true

require_relative '../environment/identity'

module Datadog
  module Core
    module Utils
      # Monkey patches Process.spawn to inject session lineage env vars
      # (_DD_ROOT_RB_SESSION_ID, _DD_PARENT_RB_SESSION_ID) into the child's
      # environment so exec-based child processes can reconstruct process lineage.
      module SpawnMonkeyPatch
        def self.apply!
          return false unless ::Process.respond_to?(:spawn)

          ::Process.singleton_class.prepend(ProcessSpawnPatch)

          true
        end

        module ProcessSpawnPatch
          def spawn(*args, **opts)
            args = SpawnMonkeyPatch.inject_lineage_envs(args)
            super(*args, **opts)
          end
        end

        class << self
          def inject_lineage_envs(args)
            lineage = Core::Environment::Identity.runtime_propagation_envs

            if args.first.is_a?(Hash)
              # env hash provided: merge lineage into it
              env = args.first.merge(lineage)
              [env, *args.drop(1)]
            else
              # no env hash: prepend ENV merged with lineage
              env = ENV.to_h.merge(lineage)
              [env, *args]
            end
          end
        end
      end
    end
  end
end
