module Datadog
  module Ext
    # Defines constants for Git tags
    module Git
      BRANCH = 'git.branch'.freeze
      COMMIT_SHA = 'git.commit.sha'.freeze
      DEPRECATED_COMMIT_SHA = 'git.commit_sha'.freeze
      REPOSITORY_URL = 'git.repository_url'.freeze
      TAG = 'git.tag'.freeze
    end
  end
end
