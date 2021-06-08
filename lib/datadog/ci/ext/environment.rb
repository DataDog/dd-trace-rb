require 'ddtrace/ext/git'

module Datadog
  module CI
    module Ext
      # Defines constants for CI tags
      # rubocop:disable Metrics/ModuleLength:
      module Environment
        TAG_STAGE_NAME = 'ci.stage.name'.freeze
        TAG_JOB_NAME = 'ci.job.name'.freeze
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
          ['TRAVIS'.freeze, :extract_travis],
          ['BITRISE_BUILD_SLUG'.freeze, :extract_bitrise]
        ].freeze

        module_function

        def tags(env)
          provider = PROVIDERS.find { |c| env.key? c[0] }
          return {} if provider.nil?

          tags = send(provider[1], env)

          tags[Datadog::Ext::Git::TAG_TAG] = normalize_ref(tags[Datadog::Ext::Git::TAG_TAG])
          tags.delete(Datadog::Ext::Git::TAG_BRANCH) unless tags[Datadog::Ext::Git::TAG_TAG].nil?
          tags[Datadog::Ext::Git::TAG_BRANCH] = normalize_ref(tags[Datadog::Ext::Git::TAG_BRANCH])
          tags[Datadog::Ext::Git::TAG_REPOSITORY_URL] = filter_sensitive_info(tags[Datadog::Ext::Git::TAG_REPOSITORY_URL])

          # Expand ~
          workspace_path = tags[TAG_WORKSPACE_PATH]
          if !workspace_path.nil? && (workspace_path == '~' || workspace_path.start_with?('~/'))
            tags[TAG_WORKSPACE_PATH] = File.expand_path(workspace_path)
          end
          tags.reject { |_, v| v.nil? }
        end

        def normalize_ref(name)
          refs = %r{^refs/(heads/)?}
          origin = %r{^origin/}
          tags = %r{^tags/}
          name.gsub(refs, '').gsub(origin, '').gsub(tags, '') unless name.nil?
        end

        def filter_sensitive_info(url)
          url.gsub(%r{(https?://)[^/]*@}, '\1') unless url.nil?
        end

        # CI providers

        def extract_appveyor(env)
          url = "https://ci.appveyor.com/project/#{env['APPVEYOR_REPO_NAME']}/builds/#{env['APPVEYOR_BUILD_ID']}"

          if env['APPVEYOR_REPO_PROVIDER'] == 'github'
            repository = "https://github.com/#{env['APPVEYOR_REPO_NAME']}.git"
            commit = env['APPVEYOR_REPO_COMMIT']
            branch = (env['APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH'] || env['APPVEYOR_REPO_BRANCH'])
            tag = env['APPVEYOR_REPO_TAG_NAME']
          end

          {
            TAG_PROVIDER_NAME => 'appveyor',
            Datadog::Ext::Git::TAG_REPOSITORY_URL => repository,
            Datadog::Ext::Git::TAG_COMMIT_SHA => commit,
            TAG_WORKSPACE_PATH => env['APPVEYOR_BUILD_FOLDER'],
            TAG_PIPELINE_ID => env['APPVEYOR_BUILD_ID'],
            TAG_PIPELINE_NAME => env['APPVEYOR_REPO_NAME'],
            TAG_PIPELINE_NUMBER => env['APPVEYOR_BUILD_NUMBER'],
            TAG_PIPELINE_URL => url,
            TAG_JOB_URL => url,
            Datadog::Ext::Git::TAG_BRANCH => branch,
            Datadog::Ext::Git::TAG_TAG => tag
          }
        end

        def extract_azure_pipelines(env)
          if env['SYSTEM_TEAMFOUNDATIONSERVERURI'] && env['SYSTEM_TEAMPROJECTID'] && env['BUILD_BUILDID']
            base_url = "#{env['SYSTEM_TEAMFOUNDATIONSERVERURI']}#{env['SYSTEM_TEAMPROJECTID']}" \
              "/_build/results?buildId=#{env['BUILD_BUILDID']}"
            pipeline_url = base_url
            job_url = base_url + "&view=logs&j=#{env['SYSTEM_JOBID']}&t=#{env['SYSTEM_TASKINSTANCEID']}"
          else
            pipeline_url = job_url = nil
          end
          branch_or_tag = (
            env['SYSTEM_PULLREQUEST_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCHNAME']
          )
          if branch_or_tag.include? 'tags/'
            branch = nil
            tag = branch_or_tag
          else
            branch = branch_or_tag
            tag = nil
          end
          {
            TAG_PROVIDER_NAME => 'azurepipelines',
            TAG_WORKSPACE_PATH => env['BUILD_SOURCESDIRECTORY'],
            TAG_PIPELINE_ID => env['BUILD_BUILDID'],
            TAG_PIPELINE_NAME => env['BUILD_DEFINITIONNAME'],
            TAG_PIPELINE_NUMBER => env['BUILD_BUILDID'],
            TAG_PIPELINE_URL => pipeline_url,
            TAG_JOB_URL => job_url,
            Datadog::Ext::Git::TAG_REPOSITORY_URL => (
              env['SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI'] \
              || env['BUILD_REPOSITORY_URI']
            ),
            Datadog::Ext::Git::TAG_COMMIT_SHA => (env['SYSTEM_PULLREQUEST_SOURCECOMMITID'] || env['BUILD_SOURCEVERSION']),
            Datadog::Ext::Git::TAG_BRANCH => branch,
            Datadog::Ext::Git::TAG_TAG => tag
          }
        end

        def extract_bitbucket(env)
          url = "https://bitbucket.org/#{env['BITBUCKET_REPO_FULL_NAME']}/addon/pipelines/home#" \
            "!/results/#{env['BITBUCKET_BUILD_NUMBER']}"
          {
            Datadog::Ext::Git::TAG_BRANCH => env['BITBUCKET_BRANCH'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['BITBUCKET_COMMIT'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['BITBUCKET_GIT_SSH_ORIGIN'],
            Datadog::Ext::Git::TAG_TAG => env['BITBUCKET_TAG'],
            TAG_JOB_URL => url,
            TAG_PIPELINE_ID => env['BITBUCKET_PIPELINE_UUID'] ? env['BITBUCKET_PIPELINE_UUID'].tr('{}', '') : None,
            TAG_PIPELINE_NAME => env['BITBUCKET_REPO_FULL_NAME'],
            TAG_PIPELINE_NUMBER => env['BITBUCKET_BUILD_NUMBER'],
            TAG_PIPELINE_URL => url,
            TAG_PROVIDER_NAME => 'bitbucket',
            TAG_WORKSPACE_PATH => env['BITBUCKET_CLONE_DIR']
          }
        end

        def extract_buildkite(env)
          {
            Datadog::Ext::Git::TAG_BRANCH => env['BUILDKITE_BRANCH'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['BUILDKITE_COMMIT'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['BUILDKITE_REPO'],
            Datadog::Ext::Git::TAG_TAG => env['BUILDKITE_TAG'],
            TAG_PIPELINE_ID => env['BUILDKITE_BUILD_ID'],
            TAG_PIPELINE_NAME => env['BUILDKITE_PIPELINE_SLUG'],
            TAG_PIPELINE_NUMBER => env['BUILDKITE_BUILD_NUMBER'],
            TAG_PIPELINE_URL => env['BUILDKITE_BUILD_URL'],
            TAG_JOB_URL => "#{env['BUILDKITE_BUILD_URL']}##{env['BUILDKITE_JOB_ID']}",
            TAG_PROVIDER_NAME => 'buildkite',
            TAG_WORKSPACE_PATH => env['BUILDKITE_BUILD_CHECKOUT_PATH']
          }
        end

        def extract_circle_ci(env)
          {
            Datadog::Ext::Git::TAG_BRANCH => env['CIRCLE_BRANCH'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['CIRCLE_SHA1'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['CIRCLE_REPOSITORY_URL'],
            Datadog::Ext::Git::TAG_TAG => env['CIRCLE_TAG'],
            TAG_PIPELINE_ID => env['CIRCLE_WORKFLOW_ID'],
            TAG_PIPELINE_NAME => env['CIRCLE_PROJECT_REPONAME'],
            TAG_PIPELINE_NUMBER => env['CIRCLE_BUILD_NUM'],
            TAG_PIPELINE_URL => env['CIRCLE_BUILD_URL'],
            TAG_JOB_URL => env['CIRCLE_BUILD_URL'],
            TAG_PROVIDER_NAME => 'circleci',
            TAG_WORKSPACE_PATH => env['CIRCLE_WORKING_DIRECTORY']
          }
        end

        def extract_github_actions(env)
          branch_or_tag = (env['GITHUB_HEAD_REF'] || env['GITHUB_REF'])
          if branch_or_tag.include? 'tags/'
            branch = nil
            tag = branch_or_tag
          else
            branch = branch_or_tag
            tag = nil
          end
          {
            Datadog::Ext::Git::TAG_BRANCH => branch,
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['GITHUB_SHA'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => "https://github.com/#{env['GITHUB_REPOSITORY']}.git",
            Datadog::Ext::Git::TAG_TAG => tag,
            TAG_JOB_URL => "https://github.com/#{env['GITHUB_REPOSITORY']}/commit/#{env['GITHUB_SHA']}/checks",
            TAG_PIPELINE_ID => env['GITHUB_RUN_ID'],
            TAG_PIPELINE_NAME => env['GITHUB_WORKFLOW'],
            TAG_PIPELINE_NUMBER => env['GITHUB_RUN_NUMBER'],
            TAG_PIPELINE_URL => "https://github.com/#{env['GITHUB_REPOSITORY']}/commit/#{env['GITHUB_SHA']}/checks",
            TAG_PROVIDER_NAME => 'github',
            TAG_WORKSPACE_PATH => env['GITHUB_WORKSPACE']
          }
        end

        def extract_gitlab(env)
          url = env['CI_PIPELINE_URL']
          url = url.gsub(%r{/-/pipelines/}, '/pipelines/') unless url.nil?
          {
            Datadog::Ext::Git::TAG_BRANCH => env['CI_COMMIT_BRANCH'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['CI_COMMIT_SHA'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['CI_REPOSITORY_URL'],
            Datadog::Ext::Git::TAG_TAG => env['CI_COMMIT_TAG'],
            TAG_STAGE_NAME => env['CI_JOB_STAGE'],
            TAG_JOB_NAME => env['CI_JOB_NAME'],
            TAG_JOB_URL => env['CI_JOB_URL'],
            TAG_PIPELINE_ID => env['CI_PIPELINE_ID'],
            TAG_PIPELINE_NAME => env['CI_PROJECT_PATH'],
            TAG_PIPELINE_NUMBER => env['CI_PIPELINE_IID'],
            TAG_PIPELINE_URL => url,
            TAG_PROVIDER_NAME => 'gitlab',
            TAG_WORKSPACE_PATH => env['CI_PROJECT_DIR']
          }
        end

        def extract_jenkins(env)
          branch_or_tag = env['GIT_BRANCH']
          if branch_or_tag.include? 'tags/'
            branch = nil
            tag = branch_or_tag
          else
            branch = branch_or_tag
            tag = nil
          end
          name = env['JOB_NAME']
          name = name.gsub("/#{normalize_ref(branch)}", '') unless name.nil? || branch.nil?
          name = name.split('/').reject { |v| v.nil? || v.include?('=') }.join('/') unless name.nil?
          {
            Datadog::Ext::Git::TAG_BRANCH => branch,
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['GIT_COMMIT'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['GIT_URL'],
            Datadog::Ext::Git::TAG_TAG => tag,
            TAG_PIPELINE_ID => env['BUILD_TAG'],
            TAG_PIPELINE_NAME => name,
            TAG_PIPELINE_NUMBER => env['BUILD_NUMBER'],
            TAG_PIPELINE_URL => env['BUILD_URL'],
            TAG_PROVIDER_NAME => 'jenkins',
            TAG_WORKSPACE_PATH => env['WORKSPACE']
          }
        end

        def extract_teamcity(env)
          {
            TAG_PROVIDER_NAME => 'teamcity',
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['BUILD_VCS_URL'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['BUILD_VCS_NUMBER'],
            TAG_WORKSPACE_PATH => env['BUILD_CHECKOUTDIR'],
            TAG_PIPELINE_ID => env['BUILD_ID'],
            TAG_PIPELINE_NUMBER => env['BUILD_NUMBER'],
            TAG_PIPELINE_URL => (
              env['SERVER_URL'] && env['BUILD_ID'] ? "#{env['SERVER_URL']}/viewLog.html?buildId=#{env['SERVER_URL']}" : nil
            )
          }
        end

        def extract_travis(env)
          {
            Datadog::Ext::Git::TAG_BRANCH => (env['TRAVIS_PULL_REQUEST_BRANCH'] || env['TRAVIS_BRANCH']),
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['TRAVIS_COMMIT'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => "https://github.com/#{env['TRAVIS_REPO_SLUG']}.git",
            Datadog::Ext::Git::TAG_TAG => env['TRAVIS_TAG'],
            TAG_JOB_URL => env['TRAVIS_JOB_WEB_URL'],
            TAG_PIPELINE_ID => env['TRAVIS_BUILD_ID'],
            TAG_PIPELINE_NAME => env['TRAVIS_REPO_SLUG'],
            TAG_PIPELINE_NUMBER => env['TRAVIS_BUILD_NUMBER'],
            TAG_PIPELINE_URL => env['TRAVIS_BUILD_WEB_URL'],
            TAG_PROVIDER_NAME => 'travisci',
            TAG_WORKSPACE_PATH => env['TRAVIS_BUILD_DIR']
          }
        end

        def extract_bitrise(env)
          commit = (
            env['BITRISE_GIT_COMMIT'] || env['GIT_CLONE_COMMIT_HASH']
          )
          branch = (
            env['BITRISEIO_GIT_BRANCH_DEST'] || env['BITRISE_GIT_BRANCH']
          )
          {
            TAG_PROVIDER_NAME => 'bitrise',
            TAG_PIPELINE_ID => env['BITRISE_BUILD_SLUG'],
            TAG_PIPELINE_NAME => env['BITRISE_APP_TITLE'],
            TAG_PIPELINE_NUMBER => env['BITRISE_BUILD_NUMBER'],
            TAG_PIPELINE_URL => env['BITRISE_BUILD_URL'],
            TAG_WORKSPACE_PATH => env['BITRISE_SOURCE_DIR'],
            Datadog::Ext::Git::TAG_REPOSITORY_URL => env['GIT_REPOSITORY_URL'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => commit,
            Datadog::Ext::Git::TAG_BRANCH => branch,
            Datadog::Ext::Git::TAG_TAG => env['BITRISE_GIT_TAG']
          }
        end
      end
      # rubocop:enable Metrics/ModuleLength:
    end
  end
end
