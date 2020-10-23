module Datadog
  module Ext
    module CI
      module AzurePipelines
        ENV_KEY = 'TF_BUILD'.freeze

        def self.extract(env)
          pipeline_url = "#{env['SYSTEM_TEAMFOUNDATIONCOLLECTIONURI']}#{env['SYSTEM_TEAMPROJECT']}/_build/results?buildId: #{env['BUILD_BUILDID']}&_a: summary" if env['SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'] && env['SYSTEM_TEAMPROJECT'] && env['BUILD_BUILDID']
          {
            provider_name: 'azurepipelines',
            workspace_path: env['BUILD_SOURCESDIRECTORY'],
            pipeline_id: env['BUILD_BUILDID'],
            pipeline_name: env['BUILD_DEFINITIONNAME'],
            pipeline_number: env['BUILD_BUILDNUMBER'],
            pipeline_url: pipeline_url,
            repository_url: env['BUILD_REPOSITORY_URI'],
            commit_sha: env['SYSTEM_PULLREQUEST_SOURCECOMMITID'] || env['BUILD_SOURCEVERSION'],
            branch: (
                  env['SYSTEM_PULLREQUEST_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCHNAME']
            )
          }
        end
      end
    end
  end
end
