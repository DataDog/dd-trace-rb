module Datadog
  module Ext
    module CI
      module Teamcity
        ENV_KEY = 'TEAMCITY_VERSION'.freeze

        def self.extract(env)
          {
            provider_name: 'teamcity',
            repository_url: env['BUILD_VCS_URL'],
            commit_sha: env['BUILD_VCS_NUMBER'],
            workspace_path: env['BUILD_CHECKOUTDIR'],
            pipeline_id: env['BUILD_ID'],
            pipeline_number: env['BUILD_NUMBER'],
            pipeline_url: env['SERVER_URL'] && env['BUILD_ID'] ? "#{env['SERVER_URL']}/viewLog.html?buildId: #{env['SERVER_URL']}" : nil
          }
        end
      end
    end
  end
end
