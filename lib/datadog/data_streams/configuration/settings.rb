# frozen_string_literal: true

require_relative '../../core/environment/variable_helpers'
require_relative '../ext'

module Datadog
  module DataStreams
    module Configuration
      # Configuration settings for Data Streams Monitoring.
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
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
                o.env Ext::ENV_ENABLED
                o.default false
              end

              # The interval (in seconds) at which Data Streams Monitoring stats are flushed.
              #
              # @default 10.0
              # @env '_DD_TRACE_STATS_WRITER_INTERVAL'
              # @return [Float]
              # @!visibility private
              option :interval do |o|
                o.type :float
                o.env '_DD_TRACE_STATS_WRITER_INTERVAL'
                o.default 10.0
              end
            end
          end
        end
      end
    end
  end
end
