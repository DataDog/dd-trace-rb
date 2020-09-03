# frozen_string_literal: true

require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/que/ext'
require 'ddtrace/contrib/que/configuration/settings'
require 'ddtrace/contrib/que/patcher'

module Datadog
  module Contrib
    module Que
      # Description of Que integration
      class Integration
        include Datadog::Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.0.0.beta2')

        register_as :que, auto_patch: true

        def self.version
          Gem.loaded_specs[Datadog::Contrib::Que::Ext::APP] &&
            Gem.loaded_specs[Datadog::Contrib::Que::Ext::APP].version
        end

        def self.loaded?
          !defined?(::Que).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
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
