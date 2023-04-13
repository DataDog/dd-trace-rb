module Datadog
  module Core
    module Git
      # Defines constants for Git tags
      module Ext
        TAG_BRANCH = 'git.branch'.freeze
        TAG_REPOSITORY_URL = 'git.repository_url'.freeze
        TAG_TAG = 'git.tag'.freeze

        TAG_COMMIT_AUTHOR_DATE = 'git.commit.author.date'.freeze
        TAG_COMMIT_AUTHOR_EMAIL = 'git.commit.author.email'.freeze
        TAG_COMMIT_AUTHOR_NAME = 'git.commit.author.name'.freeze
        TAG_COMMIT_COMMITTER_DATE = 'git.commit.committer.date'.freeze
        TAG_COMMIT_COMMITTER_EMAIL = 'git.commit.committer.email'.freeze
        TAG_COMMIT_COMMITTER_NAME = 'git.commit.committer.name'.freeze
        TAG_COMMIT_MESSAGE = 'git.commit.message'.freeze
        TAG_COMMIT_SHA = 'git.commit.sha'.freeze

        ENV_REPOSITORY_URL = 'DD_GIT_REPOSITORY_URL'.freeze
        ENV_COMMIT_SHA = 'DD_GIT_COMMIT_SHA'.freeze
        ENV_BRANCH = 'DD_GIT_BRANCH'.freeze
        ENV_TAG = 'DD_GIT_TAG'.freeze
        ENV_COMMIT_MESSAGE = 'DD_GIT_COMMIT_MESSAGE'.freeze
        ENV_COMMIT_AUTHOR_NAME = 'DD_GIT_COMMIT_AUTHOR_NAME'.freeze
        ENV_COMMIT_AUTHOR_EMAIL = 'DD_GIT_COMMIT_AUTHOR_EMAIL'.freeze
        ENV_COMMIT_AUTHOR_DATE = 'DD_GIT_COMMIT_AUTHOR_DATE'.freeze
        ENV_COMMIT_COMMITTER_NAME = 'DD_GIT_COMMIT_COMMITTER_NAME'.freeze
        ENV_COMMIT_COMMITTER_EMAIL = 'DD_GIT_COMMIT_COMMITTER_EMAIL'.freeze
        ENV_COMMIT_COMMITTER_DATE = 'DD_GIT_COMMIT_COMMITTER_DATE'.freeze
      end
    end
  end
end
