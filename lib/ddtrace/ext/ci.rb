require 'ddtrace/ext/git'

module Datadog
  module Ext
    # Defines constants for CI tags
    # rubocop:disable Metrics/ModuleLength:
    module CI
      TAG_JOB_URL = 'ci.job.url'.freeze
      TAG_PIPELINE_ID = 'ci.pipeline.id'.freeze
      TAG_PIPELINE_NAME = 'ci.pipeline.name'.freeze
      TAG_PIPELINE_NUMBER = 'ci.pipeline.number'.freeze
      TAG_PIPELINE_URL = 'ci.pipeline.url'.freeze
      TAG_PROVIDER_NAME = 'ci.provider.name'.freeze
      TAG_WORKSPACE_PATH = 'ci.workspace_path'.freeze

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

      module_function

      def tags(env)
        provider = PROVIDERS.find { |c| env.key? c[0] }
        return {} if provider.nil?
        tags = send(provider[1], env).reject { |_, v| v.nil? }
        tags[Git::TAG_BRANCH] = tags[Git::TAG_BRANCH].gsub(%r{^refs/(heads/)?}, '') if tags.key? Git::TAG_BRANCH
        tags[Git::TAG_DEPRECATED_COMMIT_SHA] = tags[Git::TAG_COMMIT_SHA] if tags.key? Git::TAG_COMMIT_SHA
        tags
      end

      # CI providers

      def extract_appveyor(env)
        {
          TAG_PROVIDER_NAME => 'appveyor',
          Git::TAG_REPOSITORY_URL => env['APPVEYOR_REPO_NAME'],
          Git::TAG_COMMIT_SHA => env['APPVEYOR_REPO_COMMIT'],
          WORKSPACE_PATH => env['APPVEYOR_BUILD_FOLDER'],
          TAG_PIPELINE_ID => env['APPVEYOR_BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['APPVEYOR_BUILD_NUMBER'],
          TAG_PIPELINE_URL => "https://ci.appveyor.com/project/#{env['APPVEYOR_PROJECT_SLUG']}" \
            "/builds/#{env['APPVEYOR_BUILD_ID']}",
          Git::TAG_BRANCH => (env['APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH'] || env['APPVEYOR_REPO_BRANCH'])
        }
      end

      def extract_azure_pipelines(env)
        if env['SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'] && env['SYSTEM_TEAMPROJECT'] && env['BUILD_BUILDID']
          pipeline_url = "#{env['SYSTEM_TEAMFOUNDATIONCOLLECTIONURI']}#{env['SYSTEM_TEAMPROJECT']}" \
            "/_build/results?buildId=#{env['BUILD_BUILDID']}&_a=summary"
        end
        {
          TAG_PROVIDER_NAME => 'azurepipelines',
          WORKSPACE_PATH => env['BUILD_SOURCESDIRECTORY'],
          TAG_PIPELINE_ID => env['BUILD_BUILDID'],
          TAG_PIPELINE_NAME => env['BUILD_DEFINITIONNAME'],
          TAG_PIPELINE_NUMBER => env['BUILD_BUILDNUMBER'],
          TAG_PIPELINE_URL => pipeline_url,
          Git::TAG_REPOSITORY_URL => env['BUILD_REPOSITORY_URI'],
          Git::TAG_COMMIT_SHA => env['SYSTEM_PULLREQUEST_SOURCECOMMITID'] || env['BUILD_SOURCEVERSION'],
          Git::TAG_BRANCH => (
            env['SYSTEM_PULLREQUEST_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCHNAME']
          )
        }
      end

      def extract_bitbucket(env)
        {
          TAG_PROVIDER_NAME => 'bitbucketpipelines',
          Git::TAG_REPOSITORY_URL => env['BITBUCKET_GIT_SSH_ORIGIN'],
          Git::TAG_COMMIT_SHA => env['BITBUCKET_COMMIT'],
          WORKSPACE_PATH => env['BITBUCKET_CLONE_DIR'],
          TAG_PIPELINE_ID => env['BITBUCKET_PIPELINE_UUID'],
          TAG_PIPELINE_NUMBER => env['BITBUCKET_BUILD_NUMBER']
        }
      end

      def extract_buildkite(env)
        {
          TAG_PROVIDER_NAME => 'buildkite',
          Git::TAG_REPOSITORY_URL => env['BUILDKITE_REPO'],
          Git::TAG_COMMIT_SHA => env['BUILDKITE_COMMIT'],
          WORKSPACE_PATH => env['BUILDKITE_BUILD_CHECKOUT_PATH'],
          TAG_PIPELINE_ID => env['BUILDKITE_BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['BUILDKITE_BUILD_NUMBER'],
          TAG_PIPELINE_URL => env['BUILDKITE_BUILD_URL'],
          Git::TAG_BRANCH => env['BUILDKITE_BRANCH']
        }
      end

      def extract_circle_ci(env)
        {
          TAG_PROVIDER_NAME => 'circleci',
          Git::TAG_REPOSITORY_URL => env['CIRCLE_REPOSITORY_URL'],
          Git::TAG_COMMIT_SHA => env['CIRCLE_SHA1'],
          WORKSPACE_PATH => env['CIRCLE_WORKING_DIRECTORY'],
          TAG_PIPELINE_NUMBER => env['CIRCLE_BUILD_NUM'],
          TAG_PIPELINE_URL => env['CIRCLE_BUILD_URL'],
          Git::TAG_BRANCH => env['CIRCLE_BRANCH']
        }
      end

      def extract_github_actions(env)
        {
          TAG_PROVIDER_NAME => 'github',
          Git::TAG_REPOSITORY_URL => env['GITHUB_REPOSITORY'],
          Git::TAG_COMMIT_SHA => env['GITHUB_SHA'],
          WORKSPACE_PATH => env['GITHUB_WORKSPACE'],
          TAG_PIPELINE_ID => env['GITHUB_RUN_ID'],
          TAG_PIPELINE_NUMBER => env['GITHUB_RUN_NUMBER'],
          TAG_PIPELINE_URL => "#{env['GITHUB_REPOSITORY']}/commit/#{env['GITHUB_SHA']}/checks",
          Git::TAG_BRANCH => env['GITHUB_REF']
        }
      end

      def extract_gitlab(env)
        {
          TAG_PROVIDER_NAME => 'gitlab',
          Git::TAG_REPOSITORY_URL => env['CI_REPOSITORY_URL'],
          Git::TAG_COMMIT_SHA => env['CI_COMMIT_SHA'],
          WORKSPACE_PATH => env['CI_PROJECT_DIR'],
          TAG_PIPELINE_ID => env['CI_PIPELINE_ID'],
          TAG_PIPELINE_NUMBER => env['CI_PIPELINE_IID'],
          TAG_PIPELINE_URL => env['CI_PIPELINE_URL'],
          TAG_JOB_URL => env['CI_JOB_URL'],
          Git::TAG_BRANCH => env['CI_COMMIT_BRANCH'] || env['CI_COMMIT_REF_NAME']
        }
      end

      def extract_jenkins(env)
        {
          TAG_PROVIDER_NAME => 'jenkins',
          Git::TAG_REPOSITORY_URL => env['GIT_URL'],
          Git::TAG_COMMIT_SHA => env['GIT_COMMIT'],
          WORKSPACE_PATH => env['WORKSPACE'],
          TAG_PIPELINE_ID => env['BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['BUILD_NUMBER'],
          TAG_PIPELINE_URL => env['BUILD_URL'],
          TAG_JOB_URL => env['JOB_URL'],
          Git::TAG_BRANCH => env['GIT_BRANCH'].nil? ? nil : env['GIT_BRANCH'].gsub(%r{^origin/}, '')
        }
      end

      def extract_teamcity(env)
        {
          TAG_PROVIDER_NAME => 'teamcity',
          Git::TAG_REPOSITORY_URL => env['BUILD_VCS_URL'],
          Git::TAG_COMMIT_SHA => env['BUILD_VCS_NUMBER'],
          WORKSPACE_PATH => env['BUILD_CHECKOUTDIR'],
          TAG_PIPELINE_ID => env['BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['BUILD_NUMBER'],
          TAG_PIPELINE_URL => (
            env['SERVER_URL'] && env['BUILD_ID'] ? "#{env['SERVER_URL']}/viewLog.html?buildId=#{env['SERVER_URL']}" : nil
          )
        }
      end

      def extract_travis(env)
        {
          TAG_PROVIDER_NAME => 'travis',
          Git::TAG_REPOSITORY_URL => env['TRAVIS_REPO_SLUG'],
          Git::TAG_COMMIT_SHA => env['TRAVIS_COMMIT'],
          WORKSPACE_PATH => env['TRAVIS_BUILD_DIR'],
          TAG_PIPELINE_ID => env['TRAVIS_BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['TRAVIS_BUILD_NUMBER'],
          TAG_PIPELINE_URL => env['TRAVIS_BUILD_WEB_URL'],
          TAG_JOB_URL => env['TRAVIS_JOB_WEB_URL'],
          Git::TAG_BRANCH => env['TRAVIS_PULL_REQUEST_BRANCH'] || env['TRAVIS_BRANCH']
        }
      end
    end
  end
end
