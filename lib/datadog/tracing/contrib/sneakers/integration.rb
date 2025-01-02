# frozen_string_literal: true

require_relative '../integration'
require_relative 'ext'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Sneakers
        # Description of Sneakers integration
        class Integration
          include Contrib::Integration

          MINIMUM_SNEAKERS_VERSION = Gem::Version.new('2.12.0')
          # All versions are supported. Kicks first version is 3.0.0.
          MINIMUM_KICKS_VERSION = Gem::Version.new('3.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :sneakers, auto_patch: true
          register_as_alias :sneakers, :kicks

          # Sneakers development continues in the Kicks gem.
          # The **only** thing that has changed is the gem name,
          # even the file naming and module namespacing are the same (require 'sneakers', `::Sneakers`).
          #
          # The last version of Sneakers is 2.12.0.
          # The first version of Kicks is 3.0.0. We currently support all versions of Kicks.
          #
          # @see https://github.com/jondot/sneakers/commit/9780692624c666b6db8266d2d5710f709cb0f2e2
          def self.version
            Gem.loaded_specs['sneakers']&.version || Gem.loaded_specs['kicks']&.version
          end

          def self.loaded?
            !defined?(::Sneakers).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_SNEAKERS_VERSION
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
end
