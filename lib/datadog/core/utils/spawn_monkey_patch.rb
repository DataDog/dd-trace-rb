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
          # Per-Ruby-version signature. On Ruby 3+, `**opts` preserves caller kwargs as
          # kwargs through `super`. On Ruby 2.5/2.6/2.7, `**opts` would auto-extract
          # Symbol-keyed entries from a mixed-keys positional options Hash (e.g.
          # childprocess's `options[fileno] = :close` on duplex pipes), splitting the
          # Hash and raising `TypeError` inside `Process.spawn`. Dropping it on 2.x
          # keeps the options Hash positional and intact. Same pattern as
          # `lib/datadog/core/utils/forking.rb`.
          if RUBY_VERSION >= '3'
            # Steep doesn't follow RUBY_VERSION conditionals; sig declares the 2.x form.
            def spawn(*args, **opts) # steep:ignore DifferentMethodParameterKind
              args.replace(SpawnMonkeyPatch.inject_lineage_envs(args))
              super
            end
          else
            def spawn(*args)
              args.replace(SpawnMonkeyPatch.inject_lineage_envs(args))
              super
            end
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
