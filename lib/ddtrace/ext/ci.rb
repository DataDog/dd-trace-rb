require 'ddtrace/ext/git'

module Datadog
  module Ext
    # Defines constants for CI tags
    # rubocop:disable Metrics/ModuleLength:
    module CI
      JOB_URL = 'ci.job.url'.freeze
      PIPELINE_ID = 'ci.pipeline.id'.freeze
      PIPELINE_NAME = 'ci.pipeline.name'.freeze
      PIPELINE_NUMBER = 'ci.pipeline.number'.freeze
      PIPELINE_URL = 'ci.pipeline.url'.freeze
      PROVIDER_NAME = 'ci.provider.name'.freeze
      WORKSPACE_PATH = 'ci.workspace_path'.freeze

      PROVIDERS = [
        ['APPVEYOR'.freeze, :extract_appveyor],
        ['TF_BUILD'.freeze, :extract_azure_pipelines],
        ['BITBUCKET_COMMIT'.freeze, :extract_bitbucket],
        ['BUILDKITE'.freeze, :extract_buildkite],
        ['CIRCLECI'.freeze, :extract_circle_ci],
        ['GITHUB_SHA'.freeze, :extract_github_actions],
        ['GITLAB_CI'.freeze, :extract_gitlab],
        ['JENKINS_URL'.freeze, :extract_jenkins],
        ['TEAMCITY_VERSION'.freeze, :extract_teamcity],
        ['TRAVIS'.freeze, :extract_travis]
      ].freeze

      def self.tags(env)
        provider = PROVIDERS.find { |c| env.key? c[0] }
        return {} if provider.nil?
        tags = send(provider[1], env).reject { |_, v| v.nil? }
        tags[Git::BRANCH] = tags[Git::BRANCH].gsub(%r{^refs/(heads/)?}, '') if tags.key? Git::BRANCH
        tags[Git::DEPRECATED_COMMIT_SHA] = tags[Git::COMMIT_SHA] if tags.key? Git::COMMIT_SHA
        tags
      end

      # CI providers

      def self.extract_appveyor(env)
        {
          PROVIDER_NAME => 'appveyor',
          Git::REPOSITORY_URL => env['APPVEYOR_REPO_NAME'],
          Git::COMMIT_SHA => env['APPVEYOR_REPO_COMMIT'],
          WORKSPACE_PATH => env['APPVEYOR_BUILD_FOLDER'],
          PIPELINE_ID => env['APPVEYOR_BUILD_ID'],
          PIPELINE_NUMBER => env['APPVEYOR_BUILD_NUMBER'],
          PIPELINE_URL => "https://ci.appveyor.com/project/#{env['APPVEYOR_PROJECT_SLUG']}" \
            "/builds/#{env['APPVEYOR_BUILD_ID']}",
          Git::BRANCH => (env['APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH'] || env['APPVEYOR_REPO_BRANCH'])
        }
      end

      def self.extract_azure_pipelines(env)
        if env['SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'] && env['SYSTEM_TEAMPROJECT'] && env['BUILD_BUILDID']
          pipeline_url = "#{env['SYSTEM_TEAMFOUNDATIONCOLLECTIONURI']}#{env['SYSTEM_TEAMPROJECT']}" \
            "/_build/results?buildId=#{env['BUILD_BUILDID']}&_a=summary"
        end
        {
          PROVIDER_NAME => 'azurepipelines',
          WORKSPACE_PATH => env['BUILD_SOURCESDIRECTORY'],
          PIPELINE_ID => env['BUILD_BUILDID'],
          PIPELINE_NAME => env['BUILD_DEFINITIONNAME'],
          PIPELINE_NUMBER => env['BUILD_BUILDNUMBER'],
          PIPELINE_URL => pipeline_url,
          Git::REPOSITORY_URL => env['BUILD_REPOSITORY_URI'],
          Git::COMMIT_SHA => env['SYSTEM_PULLREQUEST_SOURCECOMMITID'] || env['BUILD_SOURCEVERSION'],
          Git::BRANCH => (
            env['SYSTEM_PULLREQUEST_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCHNAME']
          )
        }
      end

      def self.extract_bitbucket(env)
        {
          PROVIDER_NAME => 'bitbucketpipelines',
          Git::REPOSITORY_URL => env['BITBUCKET_GIT_SSH_ORIGIN'],
          Git::COMMIT_SHA => env['BITBUCKET_COMMIT'],
          WORKSPACE_PATH => env['BITBUCKET_CLONE_DIR'],
          PIPELINE_ID => env['BITBUCKET_PIPELINE_UUID'],
          PIPELINE_NUMBER => env['BITBUCKET_BUILD_NUMBER']
        }
      end

      def self.extract_buildkite(env)
        {
          PROVIDER_NAME => 'buildkite',
          Git::REPOSITORY_URL => env['BUILDKITE_REPO'],
          Git::COMMIT_SHA => env['BUILDKITE_COMMIT'],
          WORKSPACE_PATH => env['BUILDKITE_BUILD_CHECKOUT_PATH'],
          PIPELINE_ID => env['BUILDKITE_BUILD_ID'],
          PIPELINE_NUMBER => env['BUILDKITE_BUILD_NUMBER'],
          PIPELINE_URL => env['BUILDKITE_BUILD_URL'],
          Git::BRANCH => env['BUILDKITE_BRANCH']
        }
      end

      def self.extract_circle_ci(env)
        {
          PROVIDER_NAME => 'circleci',
          Git::REPOSITORY_URL => env['CIRCLE_REPOSITORY_URL'],
          Git::COMMIT_SHA => env['CIRCLE_SHA1'],
          WORKSPACE_PATH => env['CIRCLE_WORKING_DIRECTORY'],
          PIPELINE_NUMBER => env['CIRCLE_BUILD_NUM'],
          PIPELINE_URL => env['CIRCLE_BUILD_URL'],
          Git::BRANCH => env['CIRCLE_BRANCH']
        }
      end

      def self.extract_github_actions(env)
        {
          PROVIDER_NAME => 'github',
          Git::REPOSITORY_URL => env['GITHUB_REPOSITORY'],
          Git::COMMIT_SHA => env['GITHUB_SHA'],
          WORKSPACE_PATH => env['GITHUB_WORKSPACE'],
          PIPELINE_ID => env['GITHUB_RUN_ID'],
          PIPELINE_NUMBER => env['GITHUB_RUN_NUMBER'],
          PIPELINE_URL => "#{env['GITHUB_REPOSITORY']}/commit/#{env['GITHUB_SHA']}/checks",
          Git::BRANCH => env['GITHUB_REF']
        }
      end

      def self.extract_gitlab(env)
        {
          PROVIDER_NAME => 'gitlab',
          Git::REPOSITORY_URL => env['CI_REPOSITORY_URL'],
          Git::COMMIT_SHA => env['CI_COMMIT_SHA'],
          WORKSPACE_PATH => env['CI_PROJECT_DIR'],
          PIPELINE_ID => env['CI_PIPELINE_ID'],
          PIPELINE_NUMBER => env['CI_PIPELINE_IID'],
          PIPELINE_URL => env['CI_PIPELINE_URL'],
          JOB_URL => env['CI_JOB_URL'],
          Git::BRANCH => env['CI_COMMIT_BRANCH'] || env['CI_COMMIT_REF_NAME']
        }
      end

      def self.extract_jenkins(env)
        {
          PROVIDER_NAME => 'jenkins',
          Git::REPOSITORY_URL => env['GIT_URL'],
          Git::COMMIT_SHA => env['GIT_COMMIT'],
          WORKSPACE_PATH => env['WORKSPACE'],
          PIPELINE_ID => env['BUILD_ID'],
          PIPELINE_NUMBER => env['BUILD_NUMBER'],
          PIPELINE_URL => env['BUILD_URL'],
          JOB_URL => env['JOB_URL'],
          Git::BRANCH => env['GIT_BRANCH'].nil? ? nil : env['GIT_BRANCH'].gsub(%r{^origin/}, '')
        }
      end

      def self.extract_teamcity(env)
        {
          PROVIDER_NAME => 'teamcity',
          Git::REPOSITORY_URL => env['BUILD_VCS_URL'],
          Git::COMMIT_SHA => env['BUILD_VCS_NUMBER'],
          WORKSPACE_PATH => env['BUILD_CHECKOUTDIR'],
          PIPELINE_ID => env['BUILD_ID'],
          PIPELINE_NUMBER => env['BUILD_NUMBER'],
          PIPELINE_URL => (
            env['SERVER_URL'] && env['BUILD_ID'] ? "#{env['SERVER_URL']}/viewLog.html?buildId=#{env['SERVER_URL']}" : nil
          )
        }
      end

      def self.extract_travis(env)
        {
          PROVIDER_NAME => 'travis',
          Git::REPOSITORY_URL => env['TRAVIS_REPO_SLUG'],
          Git::COMMIT_SHA => env['TRAVIS_COMMIT'],
          WORKSPACE_PATH => env['TRAVIS_BUILD_DIR'],
          PIPELINE_ID => env['TRAVIS_BUILD_ID'],
          PIPELINE_NUMBER => env['TRAVIS_BUILD_NUMBER'],
          PIPELINE_URL => env['TRAVIS_BUILD_WEB_URL'],
          JOB_URL => env['TRAVIS_JOB_WEB_URL'],
          Git::BRANCH => env['TRAVIS_PULL_REQUEST_BRANCH'] || env['TRAVIS_BRANCH']
        }
      end
    end
  end
end
