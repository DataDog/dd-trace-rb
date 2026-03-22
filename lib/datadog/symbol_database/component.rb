# frozen_string_literal: true

require_relative 'extractor'
require_relative 'uploader'
require_relative 'aggregator'

module Datadog
  module SymbolDatabase
    # Main component for the Symbol Database feature.
    # Coordinates extraction, batching, and upload of symbols.
    #
    # @api private
    class Component
      DEDUP_WINDOW = 1200 # 20 minutes

      class << self
        def build(settings, agent_settings, logger, telemetry: nil)
          return unless settings.respond_to?(:symbol_database) && settings.symbol_database.enabled

          unless settings.symbol_database.force_upload
            unless settings.respond_to?(:remote) && settings.remote.enabled
              logger.debug { 'symbol_database: Remote Configuration not available, cannot receive upload instruction' }
              return
            end
          end

          new(settings, agent_settings, logger, telemetry: telemetry)
        end
      end

      attr_reader :logger

      def initialize(settings, agent_settings, logger, telemetry: nil)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
        @telemetry = telemetry

        @extractor = Extractor.new(settings, logger)
        @uploader = Uploader.new(settings, agent_settings, logger)
        @aggregator = Aggregator.new(settings, logger, uploader: @uploader)

        @last_upload_timestamp = nil
        @lock = Mutex.new

        if settings.symbol_database.force_upload
          start_upload
        end
      end

      def start_upload
        @lock.synchronize do
          if @last_upload_timestamp && (Time.now - @last_upload_timestamp) < DEDUP_WINDOW
            @logger.debug { 'symbol_database: skipping upload, last upload was recent' }
            return
          end

          @last_upload_timestamp = Time.now
        end

        scopes = @extractor.extract
        scopes.each { |scope| @aggregator.add(scope) }
        @aggregator.flush
      rescue => e
        @logger.debug { "symbol_database: extraction/upload failed: #{e.class}: #{e}" }
      end

      def shutdown!(replacement = nil)
        @aggregator&.flush
        @aggregator&.stop
      rescue => e
        @logger.debug { "symbol_database: shutdown error: #{e.class}: #{e}" }
      end
    end
  end
end
