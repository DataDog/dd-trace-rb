# typed: false
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/concurrent_ruby/patcher'
require 'datadog/tracing/contrib/concurrent_ruby/configuration/settings'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # Describes the ConcurrentRuby integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('0.9')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :concurrent_ruby

          def self.version
            Gem.loaded_specs['concurrent-ruby'] && Gem.loaded_specs['concurrent-ruby'].version
          end

          def self.loaded?
            !defined?(::Concurrent::Future).nil?
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
