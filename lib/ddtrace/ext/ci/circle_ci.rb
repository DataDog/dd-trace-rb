module Datadog
  module Ext
    module CI
      module CircleCI
        ENV_KEY = 'CIRCLECI'.freeze

        def self.extract(env)
          {
            provider_name: 'circleci',
            repository_url: env['CIRCLE_REPOSITORY_URL'],
            commit_sha: env['CIRCLE_SHA1'],
            workspace_path: env['CIRCLE_WORKING_DIRECTORY'],
            pipeline_number: env['CIRCLE_BUILD_NUM'],
            pipeline_url: env['CIRCLE_BUILD_URL'],
            branch: env['CIRCLE_BRANCH']
          }
        end
      end
    end
  end
end
