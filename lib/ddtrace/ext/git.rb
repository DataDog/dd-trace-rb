module Datadog
  module Ext
    # Defines constants for Git tags
    module Git
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
    end
  end
end
