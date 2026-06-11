# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Applies the Process.spawn wrapper used to merge additional environment variables
      # into child processes.
      module SpawnMonkeyPatch
        # @param env_provider [#call] returns a Hash of env vars to merge into the child process
        def self.apply!(env_provider:)
          @env_provider = env_provider

          # Idempotent: tests, reloads, or repeated Components init must not stack prepends.
          return if ::Process.singleton_class.ancestors.include?(ProcessSpawnPatch)

          ::Process.singleton_class.prepend(ProcessSpawnPatch)
        end

        # Prepends `Process.spawn` to merge `env_provider` output into the child's environment hash.
        module ProcessSpawnPatch
          # The One and Only Correct Delegation Pattern
          if RUBY_VERSION >= '3'
            def spawn(*args, **kwargs) # steep:ignore DifferentMethodParameterKind
              super(*SpawnMonkeyPatch.inject_envs(args), **kwargs)
            end
          else
            def spawn(*args)
              super(*SpawnMonkeyPatch.inject_envs(args))
            end
            ruby2_keywords :spawn if respond_to?(:ruby2_keywords, true)
          end
        end

        # Merge the env vars from `env_provider` with the optional env `Hash` from {Process.spawn}.
        #
        # `env` is the first argument when it is a {Hash}; see MRI `spawn([env, ] *args, options)`:
        # https://docs.ruby-lang.org/en/master/Process.html#method-c-spawn
        #
        # When there is **no** leading env Hash, MRI inherits the parent's `ENV`; we prepend only the
        # `env_provider` hash so spawned children see parent env plus injections.
        #
        # When callers pass `unsetenv_others: true`, MRI only forwards the explicitly passed env Hash;
        # replacing a missing hash with DATADOG_ENV.to_h would wrongly carry over parent variables.
        # Prepending only the provider hash preserves `unsetenv_others` semantics.
        #
        # See https://docs.ruby-lang.org/en/master/Process.html#module-Process-label-Environment+Variables+-28-3Aunsetenv_others-29
        #
        # NOTE: `::Hash` (not bare `Hash`) is required because this module is nested under
        # `Datadog::Core::Utils`, and `Datadog::Core::Utils::Hash` exists.
        # Bare `Hash` resolves to that module via Module.nesting, making `Hash === some_hash`
        # silently return `false`. See https://github.com/DataDog/dd-trace-rb/issues/5621.
        def self.inject_envs(args)
          provided_env = @env_provider.call

          if ::Hash === args.first
            args[0] = args.first.merge(provided_env)
          else
            args.unshift(provided_env)
          end

          args
        end
      end
    end
  end
end
