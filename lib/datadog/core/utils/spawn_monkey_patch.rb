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

          return if ::Process.singleton_class.ancestors.include?(ProcessSpawnPatch)

          ::Process.singleton_class.prepend(ProcessSpawnPatch)
        end

        # Vessel for env_provider propagation.
        module ProcessSpawnPatch
          def spawn(*args)
            super(*SpawnMonkeyPatch.inject_envs(args))
          end
        end

        # Merge the env vars from `env_provider` with the `env` argument from {Process.spawn}.
        #
        # `env` is the first argument to {Process.spawn}, which is an optional {Hash}
        # (https://docs.ruby-lang.org/en/4.0/Process.html#method-c-spawn):
        # `Process.spawn([env, ] *args, options = {})`
        #
        # One thing to note is that parent process' (this process') environment variables are
        # inherited by default by the spawned process. They are merged with (and possibly overwritten by)
        # the env vars from the argument `env`.
        # (https://docs.ruby-lang.org/en/4.0/Process.html#module-Process-label-Environment+Variables+-28-3Aunsetenv_others-29)
        # This doesn't affect the current implementation.
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
