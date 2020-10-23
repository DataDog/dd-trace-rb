module Datadog
  module Ext
    module CI
      module Bitbucket
        ENV_KEY = 'BITBUCKET_COMMIT'.freeze

        def self.extract(env)
          {
            provider_name: 'bitbucketpipelines',
            repository_url: env['BITBUCKET_GIT_SSH_ORIGIN'],
            commit_sha: env['BITBUCKET_COMMIT'],
            workspace_path: env['BITBUCKET_CLONE_DIR'],
            pipeline_id: env['BITBUCKET_PIPELINE_UUID'],
            pipeline_number: env['BITBUCKET_BUILD_NUMBER']
          }
        end
      end
    end
  end
end
