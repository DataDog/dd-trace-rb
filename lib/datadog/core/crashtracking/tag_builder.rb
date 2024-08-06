# frozen_string_literal: true

require_relative '../utils'
require_relative '../environment/socket'
require_relative '../environment/identity'
require_relative '../environment/git'

module Datadog
  module Core
    module Crashtracking
      # Builds a hash of default plus user tags to be included in a profile
      module TagBuilder
        module_function

        def call(settings)
          # When changing or adding these, make sure they are kept in sync with
          # https://docs.google.com/spreadsheets/d/1LOGMf4c4Avbtn36uZ2SWvhIGKRPLM1BoWkUP4JYj7hA/ (Datadog internal link)
          tags = {
            'host' => Environment::Socket.hostname,
            'language' => Environment::Identity.lang,
            'process_id' => Process.pid.to_s,
            'profiler_version' => Environment::Identity.gem_datadog_version,
            'runtime' => Environment::Identity.lang, # This is known to be repeated from language, above
            'runtime_engine' => Environment::Identity.lang_engine,
            'runtime-id' => Environment::Identity.id,
            'runtime_platform' => Environment::Identity.lang_platform,
            'runtime_version' => Environment::Identity.lang_version,
          }

          tags['env'] = settings.env if settings.env
          tags['service'] = settings.service if settings.service
          tags['version'] = settings.version if settings.version
          tags['git.repository_url'] = Environment::Git.git_repository_url if Environment::Git.git_repository_url
          tags['git.commit.sha'] = Environment::Git.git_commit_sha if Environment::Git.git_commit_sha

          # Make sure everything is an utf-8 string, to avoid encoding issues in native code/libddprof/further downstream
          settings.tags.merge(tags).map do |key, value|
            [Utils.utf8_encode(key), Utils.utf8_encode(value)]
          end.to_h
        end
      end
    end
  end
end
