require 'ddtrace/ext/ci/appveyor'
require 'ddtrace/ext/ci/azure_pipelines'
require 'ddtrace/ext/ci/bitbucket'
require 'ddtrace/ext/ci/circle_ci'
require 'ddtrace/ext/ci/github_actions'
require 'ddtrace/ext/ci/gitlab'
require 'ddtrace/ext/ci/jenkins'
require 'ddtrace/ext/ci/teamcity'
require 'ddtrace/ext/ci/travis'

module Datadog
  module Ext
    module CI
      JOB_URL = 'ci.job.url'.freeze
      PIPELINE_ID = 'ci.pipeline.id'.freeze
      PIPELINE_NAME = 'ci.pipeline.name'.freeze
      PIPELINE_NUMBER = 'ci.pipeline.number'.freeze
      PIPELINE_URL = 'ci.pipeline.url'.freeze
      PROVIDER_NAME = 'ci.provider.name'.freeze
      WORKSPACE_PATH = 'ci.workspace_path'.freeze

      def self.tags(env)
        providers = CI.constants.map { |c| CI.const_get(c) }.select { |c| c.is_a? Module }
        provider = providers.find { |c| env.key? c::ENV_KEY.to_s } unless providers.nil?
        provider.extract(env) unless provider.nil?
      end
    end
  end
end
