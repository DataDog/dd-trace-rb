# frozen_string_literal: true

require_relative '../integration'
require_relative 'patcher'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        # Description of GraphQL integration
        class Integration
          include Datadog::AppSec::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.0.19')

          register_as :graphql, auto_patch: false

          def self.version
            Gem.loaded_specs['graphql'] && Gem.loaded_specs['graphql'].version
          end

          def self.loaded?
            !defined?(::GraphQL).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def self.auto_instrument?
            true
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
