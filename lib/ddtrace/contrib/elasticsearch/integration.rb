require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/elasticsearch/configuration/settings'
require 'ddtrace/contrib/elasticsearch/patcher'

module Datadog
  module Contrib
    module Elasticsearch
      # Description of Elasticsearch integration
      class Integration
        include Contrib::Integration

        register_as :elasticsearch, auto_patch: true

        def self.version
          Gem.loaded_specs['elasticsearch-transport'] \
            && Gem.loaded_specs['elasticsearch-transport'].version
        end

        def self.loaded?
          defined?(::Elasticsearch::Transport)
        end

        def self.compatible?
          super && version >= Gem::Version.new('1.0.0')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
