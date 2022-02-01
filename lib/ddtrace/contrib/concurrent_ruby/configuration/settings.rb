# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/concurrent_ruby/ext'

module Datadog
  module Contrib
    module ConcurrentRuby
      module Configuration
        # Custom settings for the ConcurrentRuby integration
        # @public_api
        class Settings < Contrib::Configuration::Settings
          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end
        end
      end
    end
  end
end
