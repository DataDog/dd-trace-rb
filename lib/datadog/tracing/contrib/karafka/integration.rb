# frozen_string_literal: true

require_relative '../integration'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Description of Kafka integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.1.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :karafka, auto_patch: false

          def self.version
            Gem.loaded_specs['karafka'] && Gem.loaded_specs['karafka'].version
          end

          def self.loaded?
            !defined?(::Karafka).nil?
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
end
