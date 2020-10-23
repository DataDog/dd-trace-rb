module Datadog
  module Ext
    module CI
      module Buildkite
        ENV_KEY = 'BUILDKITE'.freeze

        def self.extract(env)
          {
            provider_name: 'buildkite',
            repository_url: env['BUILDKITE_REPO'],
            commit_sha: env['BUILDKITE_COMMIT'],
            workspace_path: env['BUILDKITE_BUILD_CHECKOUT_PATH'],
            pipeline_id: env['BUILDKITE_BUILD_ID'],
            pipeline_number: env['BUILDKITE_BUILD_NUMBER'],
            pipeline_url: env['BUILDKITE_BUILD_URL'],
            branch: env['BUILDKITE_BRANCH']
          }
        end
      end
    end
  end
end
