# frozen_string_literal: true

require_relative '../utils'
require_relative '../environment/socket'
require_relative '../environment/identity'
require_relative '../environment/git'

module Datadog
  module Core
    module Crashtracking
      # This module builds a hash of tags
      module TagBuilder
        def self.call(settings)
          hash = {
            'host' => Environment::Socket.hostname,
            'process_id' => Process.pid.to_s,
            'runtime_engine' => Environment::Identity.lang_engine,
            'runtime-id' => Environment::Identity.id,
            'runtime_platform' => Environment::Identity.lang_platform,
            'runtime_version' => Environment::Identity.lang_version,
            'env' => settings.env,
            'service' => settings.service,
            'version' => settings.version,
            'git.repository_url' => Environment::Git.git_repository_url,
            'git.commit.sha' => Environment::Git.git_commit_sha,
            'is_crash' => true
          }.compact

          # Make sure everything is an utf-8 string, to avoid encoding issues in downstream
          settings.tags.merge(hash).each_with_object({}) do |(key, value), h|
            h[Utils.utf8_encode(key)] = Utils.utf8_encode(value)
          end
        end
      end
    end
  end
end
