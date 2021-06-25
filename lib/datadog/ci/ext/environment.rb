# frozen_string_literal: true

require 'ddtrace/ext/git'

require 'open3'

module Datadog
  module CI
    module Ext
      # Defines constants for CI tags
      # rubocop:disable Metrics/ModuleLength:
      module Environment
        TAG_JOB_NAME = 'ci.job.name'
        TAG_JOB_URL = 'ci.job.url'
        TAG_PIPELINE_ID = 'ci.pipeline.id'
        TAG_PIPELINE_NAME = 'ci.pipeline.name'
        TAG_PIPELINE_NUMBER = 'ci.pipeline.number'
        TAG_PIPELINE_URL = 'ci.pipeline.url'
        TAG_PROVIDER_NAME = 'ci.provider.name'
        TAG_STAGE_NAME = 'ci.stage.name'
        TAG_WORKSPACE_PATH = 'ci.workspace_path'

        PROVIDERS = [
          ['APPVEYOR', :extract_appveyor],
          ['TF_BUILD', :extract_azure_pipelines],
          ['BITBUCKET_COMMIT', :extract_bitbucket],
          ['BUILDKITE', :extract_buildkite],
          ['CIRCLECI', :extract_circle_ci],
          ['GITHUB_SHA', :extract_github_actions],
          ['GITLAB_CI', :extract_gitlab],
          ['JENKINS_URL', :extract_jenkins],
          ['TEAMCITY_VERSION', :extract_teamcity],
          ['TRAVIS', :extract_travis],
          ['BITRISE_BUILD_SLUG', :extract_bitrise]
        ].freeze

        module_function

        def tags(env)
          _, extractor = PROVIDERS.find { |provider_env_var, _| env.key?(provider_env_var) }
          if extractor
            tags = public_send(extractor, env)

            tags[Datadog::Ext::Git::TAG_TAG] = normalize_ref(tags[Datadog::Ext::Git::TAG_TAG])
            tags.delete(Datadog::Ext::Git::TAG_BRANCH) unless tags[Datadog::Ext::Git::TAG_TAG].nil?
            tags[Datadog::Ext::Git::TAG_BRANCH] = normalize_ref(tags[Datadog::Ext::Git::TAG_BRANCH])
            tags[Datadog::Ext::Git::TAG_REPOSITORY_URL] = filter_sensitive_info(tags[Datadog::Ext::Git::TAG_REPOSITORY_URL])

            # Expand ~
            workspace_path = tags[TAG_WORKSPACE_PATH]
            if !workspace_path.nil? && (workspace_path == '~' || workspace_path.start_with?('~/'))
              tags[TAG_WORKSPACE_PATH] = File.expand_path(workspace_path)
            end
          else
            tags = {}
          end

          # Fill out tags from local git as fallback
          extract_local_git.each do |key, value|
            tags[key] ||= value
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
            Datadog::Ext::Git::TAG_TAG => tag,
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['APPVEYOR_REPO_COMMIT_AUTHOR'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED']
          }
        end

        def extract_azure_pipelines(env)
          build_id = env['BUILD_BUILDID']

          if build_id &&
             (team_foundation_server_uri = env['SYSTEM_TEAMFOUNDATIONSERVERURI']) &&
             (team_project_id = env['SYSTEM_TEAMPROJECTID'])

            pipeline_url = "#{team_foundation_server_uri}#{team_project_id}/_build/results?buildId=#{build_id}"

            job_url = "#{pipeline_url}&view=logs&j=#{env['SYSTEM_JOBID']}&t=#{env['SYSTEM_TASKINSTANCEID']}"
          end

          branch, tag = branch_or_tag(env['SYSTEM_PULLREQUEST_SOURCEBRANCH'] ||
                                        env['BUILD_SOURCEBRANCH'] ||
                                        env['BUILD_SOURCEBRANCHNAME'])

          {
            TAG_PROVIDER_NAME => 'azurepipelines',
            TAG_WORKSPACE_PATH => env['BUILD_SOURCESDIRECTORY'],
            TAG_PIPELINE_ID => build_id,
            TAG_PIPELINE_NAME => env['BUILD_DEFINITIONNAME'],
            TAG_PIPELINE_NUMBER => build_id,
            TAG_PIPELINE_URL => pipeline_url,
            TAG_JOB_URL => job_url,
            Datadog::Ext::Git::TAG_REPOSITORY_URL =>
              env['SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI'] || env['BUILD_REPOSITORY_URI'],
            Datadog::Ext::Git::TAG_COMMIT_SHA => env['SYSTEM_PULLREQUEST_SOURCECOMMITID'] || env['BUILD_SOURCEVERSION'],
            Datadog::Ext::Git::TAG_BRANCH => branch,
            Datadog::Ext::Git::TAG_TAG => tag,
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILD_REQUESTEDFORID'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILD_REQUESTEDFOREMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILD_SOURCEVERSIONMESSAGE']
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
            TAG_PIPELINE_ID => env['BITBUCKET_PIPELINE_UUID'] ? env['BITBUCKET_PIPELINE_UUID'].tr('{}', '') : nil,
            TAG_PIPELINE_NAME => env['BITBUCKET_REPO_FULL_NAME'],
            TAG_PIPELINE_NUMBER => env['BITBUCKET_BUILD_NUMBER'],
            TAG_PIPELINE_URL => url,
            TAG_PROVIDER_NAME => 'bitbucket',
            TAG_WORKSPACE_PATH => env['BITBUCKET_CLONE_DIR'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILD_REQUESTEDFORID'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILD_REQUESTEDFOREMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILD_SOURCEVERSIONMESSAGE']
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
            TAG_WORKSPACE_PATH => env['BUILDKITE_BUILD_CHECKOUT_PATH'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILDKITE_BUILD_AUTHOR'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILDKITE_BUILD_AUTHOR_EMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILDKITE_MESSAGE']
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
            TAG_PIPELINE_URL => "https://app.circleci.com/pipelines/workflows/#{env['CIRCLE_WORKFLOW_ID']}",
            TAG_JOB_NAME => env['CIRCLE_JOB'],
            TAG_JOB_URL => env['CIRCLE_BUILD_URL'],
            TAG_PROVIDER_NAME => 'circleci',
            TAG_WORKSPACE_PATH => env['CIRCLE_WORKING_DIRECTORY'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILD_REQUESTEDFORID'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILD_REQUESTEDFOREMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILD_SOURCEVERSIONMESSAGE']
          }
        end

        def extract_github_actions(env)
          branch, tag = branch_or_tag(env['GITHUB_HEAD_REF'] || env['GITHUB_REF'])

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
            TAG_WORKSPACE_PATH => env['GITHUB_WORKSPACE'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILD_REQUESTEDFORID'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILD_REQUESTEDFOREMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILD_SOURCEVERSIONMESSAGE']
          }
        end

        def extract_gitlab(env)
          url = env['CI_PIPELINE_URL']
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
            TAG_PIPELINE_URL => (url.gsub(%r{/-/pipelines/}, '/pipelines/') if url),
            TAG_PROVIDER_NAME => 'gitlab',
            TAG_WORKSPACE_PATH => env['CI_PROJECT_DIR'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['CI_COMMIT_MESSAGE']
          }
        end

        def extract_jenkins(env)
          branch, tag = branch_or_tag(env['GIT_BRANCH'])

          if (name = env['JOB_NAME'])
            name = name.gsub("/#{normalize_ref(branch)}", '') if branch
            name = name.split('/').reject { |v| v.nil? || v.include?('=') }.join('/')
          end
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
            TAG_WORKSPACE_PATH => env['WORKSPACE'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILD_REQUESTEDFORID'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILD_REQUESTEDFOREMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILD_SOURCEVERSIONMESSAGE']
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
            ),
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => env['BUILD_REQUESTEDFORID'],
            Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => env['BUILD_REQUESTEDFOREMAIL'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BUILD_SOURCEVERSIONMESSAGE']
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
            TAG_WORKSPACE_PATH => env['TRAVIS_BUILD_DIR'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['TRAVIS_COMMIT_MESSAGE']
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
            Datadog::Ext::Git::TAG_TAG => env['BITRISE_GIT_TAG'],
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => env['BITRISE_GIT_MESSAGE']
          }
        end

        def git_commit_users
          # Get committer and author information in one command.
          output = exec_git_command("git show -s --format='%an\t%ae\t%at\t%cn\t%ce\t%ct'")
          return unless output

          fields = output.split("\t").each(&:strip!)

          {
            author_name: fields[0],
            author_email: fields[1],
            # Because we can't get a reliable UTC time from all recent versions of git
            # We have to rely on converting the date to UTC ourselves.
            author_date: Time.at(fields[2].to_i).utc.to_datetime.iso8601,
            committer_name: fields[3],
            committer_email: fields[4],
            # Because we can't get a reliable UTC time from all recent versions of git
            # We have to rely on converting the date to UTC ourselves.
            committer_date: Time.at(fields[5].to_i).utc.to_datetime.iso8601
          }
        rescue => e
          Datadog.logger.debug("Unable to read git commit users: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def git_repository_url
          exec_git_command('git ls-remote --get-url')
        rescue => e
          Datadog.logger.debug("Unable to read git repository url: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def git_commit_message
          exec_git_command('git show -s --format=%s')
        rescue => e
          Datadog.logger.debug("Unable to read git commit message: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def git_branch
          exec_git_command('git rev-parse --abbrev-ref HEAD')
        rescue => e
          Datadog.logger.debug("Unable to read git branch: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def git_commit_sha
          exec_git_command('git rev-parse HEAD')
        rescue => e
          Datadog.logger.debug("Unable to read git commit SHA: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def git_tag
          exec_git_command('git tag --points-at HEAD')
        rescue => e
          Datadog.logger.debug("Unable to read git tag: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def git_base_directory
          exec_git_command('git rev-parse --show-toplevel')
        rescue => e
          Datadog.logger.debug("Unable to read git base directory: #{e.message} at #{e.backtrace.first}")
          nil
        end

        def exec_git_command(cmd)
          out, status = Open3.capture2e(cmd)

          raise "Failed to run git command #{cmd}: #{out}" unless status.success?

          out.strip! # There's always a "\n" at the end of the command output

          return nil if out.empty?

          out
        end

        def extract_local_git
          env = {
            TAG_WORKSPACE_PATH => git_base_directory,
            Datadog::Ext::Git::TAG_REPOSITORY_URL => git_repository_url,
            Datadog::Ext::Git::TAG_COMMIT_SHA => git_commit_sha,
            Datadog::Ext::Git::TAG_BRANCH => git_branch,
            Datadog::Ext::Git::TAG_TAG => git_tag,
            Datadog::Ext::Git::TAG_COMMIT_MESSAGE => git_commit_message
          }

          if (commit_users = git_commit_users)
            env.merge!(
              Datadog::Ext::Git::TAG_COMMIT_AUTHOR_NAME => commit_users[:author_name],
              Datadog::Ext::Git::TAG_COMMIT_AUTHOR_EMAIL => commit_users[:author_email],
              Datadog::Ext::Git::TAG_COMMIT_AUTHOR_DATE => commit_users[:author_date],
              Datadog::Ext::Git::TAG_COMMIT_COMMITTER_NAME => commit_users[:committer_name],
              Datadog::Ext::Git::TAG_COMMIT_COMMITTER_EMAIL => commit_users[:committer_email],
              Datadog::Ext::Git::TAG_COMMIT_COMMITTER_DATE => commit_users[:committer_date]
            )
          end

          env
        end

        def branch_or_tag(branch_or_tag)
          branch = tag = nil
          if branch_or_tag.include?('tags/')
            tag = branch_or_tag
          else
            branch = branch_or_tag
          end

          [branch, tag]
        end
      end
      # rubocop:enable Metrics/ModuleLength:
    end
  end
end
