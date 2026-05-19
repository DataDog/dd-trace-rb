# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      module SpawnMonkeyPatch
        # @param lineage_envs_provider [#call] returns a Hash of env vars to merge into the child process
        def self.apply!(lineage_envs_provider:)
          @lineage_envs_provider = lineage_envs_provider
          ::Process.singleton_class.prepend(ProcessSpawnPatch)
          true
        end

        module ProcessSpawnPatch
          def spawn(*args, **opts)
            args.replace(SpawnMonkeyPatch.inject_lineage_envs(args))
            super
          end
        end

        # Process.spawn(env?, cmd, ...): env is optional first arg (Hash). When present, merge
        # runtime_ids into it; when absent, prepend full ENV + runtime_ids so the child inherits both.
        #
        # NOTE: `::Hash` (not bare `Hash`) is required because this module is nested under
        # `Datadog::Core::Utils`, and `Datadog::Core::Utils::Hash` exists as a refinement module.
        # Bare `Hash` resolves to that module via Module.nesting, making `Hash === some_hash`
        # silently return `false`. See https://github.com/DataDog/dd-trace-rb/issues/5621.
        def self.inject_lineage_envs(args)
          runtime_ids = @lineage_envs_provider.call
          env_provided = ::Hash === args.first

          base_env = env_provided ? args.first : DATADOG_ENV.to_h
          env = base_env.merge(runtime_ids)
          rest = env_provided ? args.drop(1) : args

          [env, *rest]
        end
      end
    end
  end
end
