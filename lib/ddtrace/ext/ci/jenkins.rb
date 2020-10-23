module Datadog
  module Ext
    module CI
      module Buildkite
        ENV_KEY = 'JENKINS_URL'.freeze

        def self.extract(env)
          {
            provider_name: 'jenkins',
            repository_url: env['GIT_URL'],
            commit_sha: env['GIT_COMMIT'],
            workspace_path: env['WORKSPACE'],
            pipeline_id: env['BUILD_ID'],
            pipeline_number: env['BUILD_NUMBER'],
            pipeline_url: env['BUILD_URL'],
            job_url: env['JOB_URL'],
            branch: env['GIT_BRANCH'].gsub(/^origin/, '')
          }
        end
      end
    end
  end
end
