module Datadog
  module Ext
    module CI
      module Travis
        ENV_KEY = 'TRAVIS'.freeze

        def self.extract(env)
          {
            provider_name: 'travis',
            repository_url: env['TRAVIS_REPO_SLUG'],
            commit_sha: env['TRAVIS_COMMIT'],
            workspace_path: env['TRAVIS_BUILD_DIR'],
            pipeline_id: env['TRAVIS_BUILD_ID'],
            pipeline_number: env['TRAVIS_BUILD_NUMBER'],
            pipeline_url: env['TRAVIS_BUILD_WEB_URL'],
            job_url: env['TRAVIS_JOB_WEB_URL'],
            branch: env['TRAVIS_PULL_REQUEST_BRANCH'] || env['TRAVIS_BRANCH']
          }
        end
      end
    end
  end
end
