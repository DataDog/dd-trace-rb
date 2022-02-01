# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/elasticsearch/configuration/settings'
require 'ddtrace/contrib/elasticsearch/patcher'

module Datadog
  module Contrib
    module Elasticsearch
      # Description of Elasticsearch integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.0.0')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :elasticsearch, auto_patch: true

        def self.version
          Gem.loaded_specs['elasticsearch-transport'] \
            && Gem.loaded_specs['elasticsearch-transport'].version
        end

        def self.loaded?
          !defined?(::Elasticsearch::Transport).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
