# frozen_string_literal: true

require_relative '../../core/environment/variable_helpers'
require_relative '../processor'

module Datadog
  module DataStreams
    module Configuration
      # Configuration settings for Data Streams Monitoring.
      # @public_api
      module Settings
        def self.extended(base)
          base.class_eval do
            # Data Streams Monitoring configuration
            # @public_api
            settings :data_streams do
              # Whether Data Streams Monitoring is enabled. When enabled, the library will
              # collect and report data lineage information for messaging systems.
              #
              # @default `DD_DATA_STREAMS_ENABLED` environment variable, otherwise `false`.
              # @return [Boolean]
              option :enabled do |o|
                o.type :bool
                o.env 'DD_DATA_STREAMS_ENABLED'
                o.default false
              end
            end
          end
        end
      end
    end
  end
end
