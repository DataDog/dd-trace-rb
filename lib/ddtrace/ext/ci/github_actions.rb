module Datadog
  module Ext
    module CI
      module GithubActions
        ENV_KEY = 'GITHUB_SHA'.freeze

        def self.extract(env)
          {
            provider_name: 'github',
            repository_url: env['GITHUB_REPOSITORY'],
            commit_sha: env['GITHUB_SHA'],
            workspace_path: env['GITHUB_WORKSPACE'],
            pipeline_id: env['GITHUB_RUN_ID'],
            pipeline_number: env['GITHUB_RUN_NUMBER'],
            pipeline_url: "#{env['GITHUB_REPOSITORY']}/commit/#{env['GITHUB_SHA']}/checks",
            branch: env['GITHUB_REF']
          }
        end
      end
    end
  end
end
