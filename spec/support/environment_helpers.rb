module EnvironmentHelpers
  module Git
    # Resets caches in this module.
    def reset_for_tests
      remove_instance_variable(:@git_repository_url) if defined?(@git_repository_url)
      remove_instance_variable(:@git_commit_sha) if defined?(@git_commit_sha)
    end
  end
end

Datadog::Core::Environment::Git.extend EnvironmentHelpers::Git
