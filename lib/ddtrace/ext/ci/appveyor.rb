module Datadog
  module Ext
    module CI
      module Appveyor
        ENV_KEY = 'APPVEYOR'.freeze

        def self.extract(env)
          {
            provider_name: 'appveyor',
            repository_url: env['APPVEYOR_REPO_NAME'],
            commit_sha: env['APPVEYOR_REPO_COMMIT'],
            workspace_path: env['APPVEYOR_BUILD_FOLDER'],
            pipeline_id: env['APPVEYOR_BUILD_ID'],
            pipeline_number: env['APPVEYOR_BUILD_NUMBER'],
            pipeline_url: "https://ci.appveyor.com/project/#{env['APPVEYOR_PROJECT_SLUG']}/builds/#{env['APPVEYOR_BUILD_ID']}",
            branch: (env['APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH'] || env['APPVEYOR_REPO_BRANCH'])
          }
        end
      end
    end
  end
end
