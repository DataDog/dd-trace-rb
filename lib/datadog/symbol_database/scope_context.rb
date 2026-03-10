# frozen_string_literal: true

require 'set'

module Datadog
  module SymbolDatabase
    # Batches extracted scopes and triggers uploads at appropriate times.
    #
    # Implements two upload triggers:
    # 1. Size-based: Immediate upload when 400 scopes collected (MAX_SCOPES)
    # 2. Time-based: Upload after 1 second of inactivity (debounce timer, not periodic)
    #
    # Also provides:
    # - Deduplication: Tracks uploaded module names to prevent re-uploads
    # - File limiting: Stops after 10,000 files to prevent runaway extraction
    # - Thread safety: Mutex-protected state for concurrent access
    #
    # Flow: Extractor → add_scope → (batch or timer) → Uploader
    # Created by: Component (during initialization)
    # Calls: Uploader.upload_scopes when batch full or timer fires
    class ScopeContext
      MAX_SCOPES = 400
      INACTIVITY_TIMEOUT = 1.0  # seconds
      MAX_FILES = 10_000

      def initialize(uploader, telemetry: nil)
        @uploader = uploader
        @telemetry = telemetry
        @scopes = []
        @mutex = Mutex.new
        @timer = nil
        @file_count = 0
        @uploaded_modules = Set.new
      end

      # Add a scope to the batch
      # @param scope [Scope] The scope to add
      def add_scope(scope)
        scopes_to_upload = nil
        timer_to_join = nil

        @mutex.synchronize do
          # Check file limit
          if @file_count >= MAX_FILES
            Datadog.logger.debug("SymDB: File limit (#{MAX_FILES}) reached, ignoring scope: #{scope.name}")
            return
          end

          @file_count += 1

          # Check if already uploaded
          return if @uploaded_modules.include?(scope.name)

          @uploaded_modules.add(scope.name)

          # Add the scope
          @scopes << scope

          # Check if batch size reached (AFTER adding)
          if @scopes.size >= MAX_SCOPES
            # Prepare for upload (clear within mutex)
            scopes_to_upload = @scopes.dup
            @scopes.clear
            if @timer
              @timer.kill
              timer_to_join = @timer
              @timer = nil
            end
          else
            # Reset inactivity timer (only if not uploading)
            reset_timer_internal
          end
        end

        # Wait for timer thread to terminate (outside mutex)
        timer_to_join&.join(0.1)

        # Upload outside mutex (if batch was full)
        perform_upload(scopes_to_upload) if scopes_to_upload
      rescue => e
        Datadog.logger.debug("SymDB: Failed to add scope: #{e.class}: #{e}")
        # Don't propagate, continue operation
      end

      # Force upload of current batch
      def flush
        scopes_to_upload = nil
        timer_to_join = nil

        @mutex.synchronize do
          return if @scopes.empty?

          scopes_to_upload = @scopes.dup
          @scopes.clear
          if @timer
            @timer.kill
            timer_to_join = @timer
            @timer = nil
          end
        end

        # Wait for timer thread to terminate (outside mutex)
        timer_to_join&.join(0.1)

        perform_upload(scopes_to_upload)
      end

      # Shutdown and upload remaining scopes
      def shutdown
        scopes_to_upload = nil
        timer_to_join = nil

        @mutex.synchronize do
          if @timer
            @timer.kill
            timer_to_join = @timer
            @timer = nil
          end

          scopes_to_upload = @scopes.dup
          @scopes.clear
        end

        # Wait for timer thread to terminate (outside mutex to avoid deadlock)
        timer_to_join&.join(0.1)

        # Upload outside mutex
        perform_upload(scopes_to_upload) unless scopes_to_upload.empty?
      end

      # Reset state (for testing)
      def reset
        timer_to_join = nil

        @mutex.synchronize do
          @scopes.clear
          if @timer
            @timer.kill
            timer_to_join = @timer
            @timer = nil
          end
          @file_count = 0
          @uploaded_modules.clear
        end

        # Wait for timer thread to actually terminate (outside mutex to avoid deadlock)
        timer_to_join&.join(0.1)
      end

      # Check if scopes are pending
      # @return [Boolean]
      def pending?
        @mutex.synchronize { @scopes.any? }
      end

      # Get current batch size
      # @return [Integer]
      def size
        @mutex.synchronize { @scopes.size }
      end

      private

      # Reset timer (must be called from within mutex)
      def reset_timer_internal
        # Cancel existing timer
        @timer&.kill

        # Start new timer thread
        @timer = Thread.new do
          sleep INACTIVITY_TIMEOUT
          # Timer fires - need to upload
          flush  # flush will acquire mutex (safe - different thread)
        end
      end

      def perform_upload(scopes)
        return if scopes.nil? || scopes.empty?

        @uploader.upload_scopes(scopes)
      rescue => e
        Datadog.logger.debug("SymDB: Upload failed: #{e.class}: #{e}")
        # Don't propagate, uploader handles retries
      end
    end
  end
end
