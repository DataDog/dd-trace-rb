module Datadog
  module Ext
    # Defines constants for Git tags
    module Git
      TAG_BRANCH = 'git.branch'.freeze
      TAG_COMMIT_SHA = 'git.commit.sha'.freeze
      TAG_DEPRECATED_COMMIT_SHA = 'git.commit_sha'.freeze
      TAG_REPOSITORY_URL = 'git.repository_url'.freeze
      TAG_TAG = 'git.tag'.freeze
    end
  end
end
