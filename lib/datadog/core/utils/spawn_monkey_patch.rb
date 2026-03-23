# frozen_string_literal: true

require_relative '../environment/identity'

module Datadog
  module Core
    module Utils
      module SpawnMonkeyPatch
        def self.apply!
          ::Process.singleton_class.prepend(ProcessSpawnPatch)
          true
        end

        module ProcessSpawnPatch
          def spawn(*args, **opts)
            args.replace(SpawnMonkeyPatch.inject_lineage_envs(args))
            super
          end
        end

        class << self
          # Process.spawn(env?, cmd, ...): env is optional first arg (Hash). When present, merge
          # runtime_ids into it; when absent, prepend full ENV + runtime_ids so the child inherits both.
          def inject_lineage_envs(args)
            runtime_ids = Core::Environment::Identity.runtime_propagation_envs
            env_provided = Hash === args.first

            base_env = env_provided ? args.first : DATADOG_ENV.to_h
            env = base_env.merge(runtime_ids)
            rest = env_provided ? args.drop(1) : args

            [env, *rest]
          end
        end
      end
    end
  end
end
