module Datadog
  module Ext
    module CI
      module Gitlab
        ENV_KEY = 'GITLAB_CI'.freeze

        def self.extract(env)
          {
            provider_name: 'gitlab',
            repository_url: env['CI_REPOSITORY_URL'],
            commit_sha: env['CI_COMMIT_SHA'],
            workspace_path: env['CI_PROJECT_DIR'],
            pipeline_id: env['CI_PIPELINE_ID'],
            pipeline_number: env['CI_PIPELINE_IID'],
            pipeline_url: env['CI_PIPELINE_URL'],
            job_url: env['CI_JOB_URL'],
            branch: env['CI_COMMIT_BRANCH'] || env['CI_COMMIT_REF_NAME']
          }
        end
      end
    end
  end
end
