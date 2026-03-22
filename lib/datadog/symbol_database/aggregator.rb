# frozen_string_literal: true

require_relative 'service_version'

module Datadog
  module SymbolDatabase
    # Batches extracted scopes and flushes them as uploads.
    #
    # @api private
    class Aggregator
      BATCH_SIZE = 400
      FLUSH_INTERVAL = 1.0

      def initialize(settings, logger, uploader:)
        @settings = settings
        @logger = logger
        @uploader = uploader
        @scopes = []
        @lock = Mutex.new
        @timer = nil
      end

      def add(scope)
        @lock.synchronize do
          @scopes << scope
          reset_timer

          if @scopes.size >= BATCH_SIZE
            flush_locked
          end
        end
      end

      def flush
        @lock.synchronize { flush_locked }
      end

      def stop
        @lock.synchronize { cancel_timer }
      end

      private

      def flush_locked
        return if @scopes.empty?
        cancel_timer

        batch = @scopes.dup
        @scopes.clear

        service_version = build_service_version(batch)

        begin
          json = service_version.to_json
          @logger.debug { "symbol_database: uploading #{batch.size} scopes" }
          @uploader.upload_with_retry(json)
        rescue => e
          @logger.debug { "symbol_database: serialization/upload failed: #{e.class}: #{e}" }
        end
      end

      def build_service_version(scopes)
        ServiceVersion.new(
          service: @settings.service || '',
          env: @settings.env || '',
          version: @settings.version || '',
          language: 'RUBY',
          scopes: scopes,
        )
      end

      def reset_timer
        cancel_timer
        @timer = Thread.new do
          sleep(FLUSH_INTERVAL)
          flush
        rescue => e
          @logger.debug { "symbol_database: timer error: #{e.class}: #{e}" }
        end
      end

      def cancel_timer
        t = @timer
        @timer = nil
        t&.kill
      end
    end
  end
end
