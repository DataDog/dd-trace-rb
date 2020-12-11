# frozen_string_literal: true

require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sneakers/ext'
require 'ddtrace/contrib/sneakers/configuration/settings'
require 'ddtrace/contrib/sneakers/patcher'

module Datadog
  module Contrib
    module Sneakers
      # Description of Sneakers integration
      class Integration
        include Datadog::Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('2.12.0')

        register_as :sneakers, auto_patch: true

        def self.version
          Gem.loaded_specs['sneakers'] && Gem.loaded_specs['sneakers'].version
        end

        def self.loaded?
          !defined?(::Sneakers).nil?
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
