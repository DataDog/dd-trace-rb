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
    #
    # @api private
    class ScopeContext
      # Maximum scopes per batch before triggering immediate upload.
      # This matches the batch size used in Java and Python tracers to ensure
      # consistent upload behavior across languages.
      MAX_SCOPES = 400
      INACTIVITY_TIMEOUT = 1.0  # seconds
      # Maximum unique files to track before stopping extraction.
      # This prevents runaway memory usage in applications with very large
      # numbers of loaded classes (e.g., heavily modularized Rails apps).
      MAX_FILES = 10_000

      # Initialize batching context.
      # @param uploader [Uploader] Uploader instance for triggering uploads
      # @param telemetry [Telemetry, nil] Optional telemetry for metrics
      # @param on_upload [Proc, nil] Optional callback called after upload (for testing)
      # @param timer_enabled [Boolean] Enable async timer (default true, false for tests)
      def initialize(uploader, telemetry: nil, on_upload: nil, timer_enabled: true)
        @uploader = uploader
        @telemetry = telemetry
        @on_upload = on_upload
        @timer_enabled = timer_enabled
        @scopes = []
        @mutex = Mutex.new
        @timer = nil
        @file_count = 0
        @uploaded_modules = Set.new
      end

      # Add a scope to the batch.
      # Triggers immediate upload if batch reaches 400 scopes.
      # Resets inactivity timer if batch not full.
      # @param scope [Scope] The scope to add
      # @return [void]
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
        @telemetry&.count('symbol_database.add_scope_error', 1)
        # Don't propagate, continue operation
      end

      # Force upload of current batch immediately.
      # @return [void]
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

      # Shutdown and upload remaining scopes.
      # @return [void]
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
        # 0.1s timeout chosen because:
        # - Short enough to not significantly delay shutdown (user experience)
        # - Long enough to give timer thread time to terminate cleanly (typical thread cleanup < 10ms)
        # - Acceptable to abandon thread if it doesn't terminate (timer just triggers upload, no critical cleanup)
        timer_to_join&.join(0.1)

        # Upload outside mutex
        perform_upload(scopes_to_upload) unless scopes_to_upload.empty?
      end

      # Reset state (for testing).
      # @return [void]
      # @api private
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
        # 0.1s timeout chosen because:
        # - Short enough to not significantly delay reset operation (test cleanup)
        # - Long enough to give timer thread time to terminate cleanly (typical thread cleanup < 10ms)
        # - Acceptable to abandon thread if it doesn't terminate (timer just triggers upload, no critical cleanup)
        timer_to_join&.join(0.1)
      end

      # Check if scopes are pending upload.
      # @return [Boolean] true if scopes waiting in batch
      def scopes_pending?
        @mutex.synchronize { @scopes.any? }
      end

      # Get current batch size.
      # @return [Integer] Number of scopes in current batch
      def size
        @mutex.synchronize { @scopes.size }
      end

      # @api private
      private

      # Reset timer (must be called from within mutex)
      # @return [void]
      def reset_timer_internal
        # Cancel existing timer and wait for it to terminate
        if @timer
          timer_to_kill = @timer
          @timer = nil
          timer_to_kill.kill
          # Wait briefly for thread to terminate to avoid thread accumulation
          # Use a very short timeout to avoid blocking the mutex for too long
          timer_to_kill.join(0.01)
        end

        # Start new timer thread (unless disabled for testing)
        return unless @timer_enabled

        @timer = Thread.new do
          sleep INACTIVITY_TIMEOUT
          # Timer fires - need to upload
          flush  # flush will acquire mutex (safe - different thread)
        rescue
          # Timer interrupted or error - ignore
        end
      end

      # Perform upload via uploader.
      # @param scopes [Array<Scope>] Scopes to upload
      # @return [void]
      def perform_upload(scopes)
        return if scopes.nil? || scopes.empty?

        @uploader.upload_scopes(scopes)
        @on_upload&.call(scopes)  # Notify tests after upload
      rescue => e
        Datadog.logger.debug("SymDB: Upload failed: #{e.class}: #{e}")
        @telemetry&.count('symbol_database.perform_upload_error', 1)
        # Don't propagate, uploader handles retries
      end
    end
  end
end
