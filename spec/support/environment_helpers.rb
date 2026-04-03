module EnvironmentHelpers
  module Git
    # No-op: git values are now read directly from the settings object on every
    # call, so there is no module-level cache to reset.
    def reset_for_tests
    end
  end
end

Datadog::Core::Environment::Git.extend EnvironmentHelpers::Git
