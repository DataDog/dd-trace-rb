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
    # Timer implementation: A single long-lived thread waits on a ConditionVariable
    # with a timeout. Each add_scope signals the CV to reset the deadline. When the
    # timeout expires without a signal, the timer fires and flushes the batch.
    # This avoids creating/destroying a thread per add_scope call.
    #
    # Flow: Extractor → add_scope → (batch or timer) → Uploader
    # Created by: Component (during initialization)
    # Calls: Uploader.upload_scopes when batch full or timer fires
    #
    # @api private
    class ScopeBatcher
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
      # @param logger [Logger] Logger for diagnostics
      # @param telemetry [Core::Telemetry::Component, nil] Telemetry for error reporting
      # @param on_upload [Proc, nil] Optional callback called after upload (for testing)
      # @param timer_enabled [Boolean] Enable async timer (default true, false for tests)
      def initialize(uploader, logger:, telemetry: nil, on_upload: nil, timer_enabled: true)
        @uploader = uploader
        @logger = logger
        @telemetry = telemetry
        @on_upload = on_upload
        @timer_enabled = timer_enabled
        @scopes = []
        @mutex = Mutex.new
        @file_count = 0
        @uploaded_modules = Set.new

        # Timer state: single long-lived thread + ConditionVariable for debounce.
        # @timer_signaled is set to true on each add_scope and cleared by the timer
        # thread after waking. This flag is needed because ConditionVariable#wait
        # does not distinguish signal vs timeout on Ruby < 3.2 (returns self in both
        # cases). The flag gives a portable way to detect whether the wakeup was a
        # signal (reset deadline) or a timeout (fire the timer).
        @timer_cv = ConditionVariable.new
        @timer_thread = nil
        @timer_stopped = false
        @timer_signaled = false
      end

      # Add a scope to the batch.
      # Triggers immediate upload if batch reaches 400 scopes.
      # Resets inactivity timer if batch not full.
      # @param scope [Scope] The scope to add
      # @return [void]
      def add_scope(scope)
        # @type var scopes_to_upload: ::Array[Scope]?
        scopes_to_upload = nil

        @mutex.synchronize do
          # Check file limit
          if @file_count >= MAX_FILES
            @logger.debug { "symdb: file limit (#{MAX_FILES}) reached, ignoring scope: #{scope.name}" }
            return
          end

          @file_count += 1

          # Check if already uploaded
          if @uploaded_modules.include?(scope.name)
            @logger.trace { "symdb: skipping #{scope.name}: already uploaded" }
            return
          end

          @uploaded_modules.add(scope.name)

          # Add the scope
          @scopes << scope

          # Check if batch size reached (AFTER adding)
          if @scopes.size >= MAX_SCOPES
            # Prepare for upload (clear within mutex)
            scopes_to_upload = @scopes.dup
            @scopes.clear
          end

          # Signal the timer thread to reset its inactivity deadline.
          # If batch was full, this is harmless — the timer will just
          # re-check and find an empty batch if it fires.
          ensure_timer_running
          @timer_signaled = true
          @timer_cv.signal
        end

        # Upload outside mutex (if batch was full)
        perform_upload(scopes_to_upload) if scopes_to_upload
      rescue => e
        @logger.debug { "symdb: failed to add scope: #{e.class}: #{e.message}" }
        @telemetry&.report(e, description: 'symdb: failed to add scope')
        # Don't propagate, continue operation
      end

      # Force upload of current batch immediately.
      # @return [void]
      def flush
        # @type var scopes_to_upload: ::Array[Scope]?
        scopes_to_upload = nil

        @mutex.synchronize do
          return if @scopes.empty?

          scopes_to_upload = @scopes.dup
          @scopes.clear
        end

        perform_upload(scopes_to_upload)
      end

      # Shutdown and upload remaining scopes.
      # @return [void]
      def shutdown
        # @type var scopes_to_upload: ::Array[Scope]?
        scopes_to_upload = nil
        # @type var thread_to_join: ::Thread?
        thread_to_join = nil

        @mutex.synchronize do
          @timer_stopped = true
          @timer_cv.signal  # Wake the timer thread so it exits

          # Capture the timer thread under the mutex so a concurrent add_scope
          # cannot create a new thread that we'd accidentally orphan when we
          # nil the field below.
          thread_to_join = @timer_thread
          @timer_thread = nil

          scopes_to_upload = @scopes.dup
          @scopes.clear
        end

        # Join the timer thread outside the mutex.
        # The thread checks @timer_stopped and exits when signaled.
        thread_to_join&.join(5)  # 5-second timeout to avoid hanging

        # Upload outside mutex
        perform_upload(scopes_to_upload) unless scopes_to_upload.nil? || scopes_to_upload.empty?
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

      private

      # Reset state. Private so production code cannot accidentally invoke it;
      # tests call via +send(:reset)+.
      # @return [void]
      def reset
        # @type var thread_to_join: ::Thread?
        thread_to_join = nil

        @mutex.synchronize do
          @scopes.clear
          @timer_stopped = true
          @timer_cv.signal
          @file_count = 0
          @uploaded_modules.clear

          # Capture under the mutex (see shutdown for rationale).
          thread_to_join = @timer_thread
          @timer_thread = nil
        end

        thread_to_join&.join(5)

        # Allow timer to be restarted after reset
        @mutex.synchronize do
          @timer_stopped = false
          @timer_signaled = false
        end
      end

      # Start the timer thread if not already running.
      # Must be called from within @mutex.synchronize.
      # @return [void]
      def ensure_timer_running
        return unless @timer_enabled
        return if @timer_thread&.alive?

        @timer_stopped = false
        @timer_signaled = false

        @timer_thread = Thread.new do
          timer_loop
        end
      end

      # Timer thread main loop. Waits on the ConditionVariable with a timeout.
      # Each signal resets the deadline (debounce). When the wait times out
      # (no signal within INACTIVITY_TIMEOUT), the batch is flushed.
      #
      # Uses @timer_signaled flag instead of ConditionVariable#wait return value
      # because Ruby < 3.2 returns self for both signal and timeout (no way to
      # distinguish). The flag is set by add_scope before signaling, and cleared
      # by the timer thread after waking.
      # @return [void]
      def timer_loop
        loop do
          should_flush = false

          @mutex.synchronize do
            return if @timer_stopped

            @timer_signaled = false
            @timer_cv.wait(@mutex, INACTIVITY_TIMEOUT)

            return if @timer_stopped

            if @timer_signaled
              # Woke up because add_scope signaled — loop back to re-wait with
              # a fresh timeout. This implements the debounce: the timeout resets
              # on every scope addition.
              next # steep:ignore BreakTypeMismatch
            end

            # Timed out (no signal within INACTIVITY_TIMEOUT). If there are
            # scopes pending, flush them. Otherwise, loop back and wait again.
            should_flush = !@scopes.empty?
          end

          if should_flush
            flush
          end
        end
      rescue => e
        @logger.debug { "symdb: timer thread error: #{e.class}: #{e.message}" }
        @telemetry&.report(e, description: 'symdb: timer thread error')
      end

      # Perform upload via uploader.
      # @param scopes [Array<Scope>] Scopes to upload
      # @return [void]
      def perform_upload(scopes)
        return if scopes.nil? || scopes.empty?

        @uploader.upload_scopes(scopes)
        @on_upload&.call(scopes)  # Notify tests after upload
      rescue => e
        @logger.debug { "symdb: upload failed: #{e.class}: #{e.message}" }
        @telemetry&.report(e, description: 'symdb: upload failed')
        # Don't propagate, uploader handles retries
      end
    end
  end
end
