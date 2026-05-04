# frozen_string_literal: true

require_relative 'extractor'
require_relative 'logger'
require_relative 'scope_batcher'
require_relative 'uploader'
require_relative '../core/utils/time'

module Datadog
  module SymbolDatabase
    # Main coordinator for symbol database upload functionality.
    #
    # Responsibilities:
    # - Lifecycle management: Initialization, shutdown, upload triggering
    # - Coordination: Connects Extractor → ScopeBatcher → Uploader
    # - Remote config handling: start_upload called by Remote module on config changes
    # - Debounce: extraction is deferred by EXTRACT_DEBOUNCE_INTERVAL seconds so
    #   reconfigurations during boot coalesce into a single extraction on the
    #   final Component instance.
    #
    # Upload flow:
    # 1. Remote config sends upload_symbols: true (or force_upload mode)
    # 2. start_upload called — schedules extraction EXTRACT_DEBOUNCE_INTERVAL
    #    seconds in the future on a per-instance scheduler thread.
    # 3. When the timer fires (no further start_upload calls reset it),
    #    extract_and_upload runs: ObjectSpace iteration → Extractor → ScopeBatcher.
    # 4. ScopeBatcher batches and triggers Uploader.
    # 5. A class-level flag is set so subsequent Component instances created via
    #    Datadog reconfiguration do not re-upload.
    #
    # Created by: Components#initialize (in Core::Configuration::Components)
    # Accessed by: Remote config receiver via Datadog.send(:components).symbol_database
    # Requires: Remote config enabled (unless force mode)
    #
    # @api private
    class Component
      # Debounce window for extraction. Multiple start_upload calls within this
      # window coalesce; the timer fires once after the window of inactivity.
      # Long enough to absorb reconfiguration cascades during Rails boot.
      EXTRACT_DEBOUNCE_INTERVAL = 5  # seconds

      # Class-level state: tracks whether any Component instance in this process
      # has performed an extract+upload. Survives Component replacement during
      # Datadog reconfiguration so duplicate uploads are prevented.
      @uploaded_this_process = false
      @upload_done_mutex = Mutex.new
      @upload_done_cv = ConditionVariable.new

      class << self
        attr_reader :upload_done_mutex, :upload_done_cv

        def uploaded_this_process?
          @upload_done_mutex.synchronize { @uploaded_this_process }
        end

        def mark_uploaded
          @upload_done_mutex.synchronize do
            @uploaded_this_process = true
            @upload_done_cv.broadcast
          end
        end

        # Reset class-level upload state. Test-only.
        # @api private
        def reset_uploaded_this_process_for_tests!
          @upload_done_mutex.synchronize { @uploaded_this_process = false }
        end
      end

      # Build a new Component if feature is enabled and dependencies met.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      # @return [Component, nil] Component instance or nil if not enabled/requirements not met
      def self.build(settings, agent_settings, logger)
        symdb_logger = SymbolDatabase::Logger.new(settings, logger)

        unless settings.respond_to?(:symbol_database) && settings.symbol_database.enabled
          symdb_logger.debug("symdb: symbol database upload not enabled, skipping")
          return
        end

        # Symbol database requires MRI Ruby 2.6+.
        # Configuration accessors (settings.symbol_database.*) remain available on all
        # platforms — only the component (upload) is disabled on unsupported engines/versions.
        unless environment_supported?(symdb_logger)
          return nil
        end

        # Requires remote config (unless force mode)
        unless settings.remote&.enabled || settings.symbol_database.internal.force_upload
          symdb_logger.debug("symdb: remote config not available and force_upload not set, skipping")
          return nil
        end

        new(settings, agent_settings, symdb_logger).tap do |component|
          # Defer extraction if force upload mode — wait for app boot to complete
          component.schedule_deferred_upload if settings.symbol_database.internal.force_upload
        end
      end

      attr_reader :settings, :last_upload_time, :upload_in_progress

      # Initialize component.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      def initialize(settings, agent_settings, logger)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger

        @extractor = Extractor.new(logger: logger, settings: settings)
        @uploader = Uploader.new(settings, agent_settings, logger: logger)
        @scope_batcher = ScopeBatcher.new(@uploader, logger: logger)

        @last_upload_time = nil
        @mutex = Mutex.new
        @upload_in_progress = false
        @upload_in_progress_cv = ConditionVariable.new
        @shutdown = false

        # Per-instance scheduler state. The scheduler thread is started lazily
        # on the first start_upload call.
        @scheduler_mutex = Mutex.new
        @scheduler_cv = ConditionVariable.new
        @scheduled_at = nil
        @scheduler_signaled = false
        @scheduler_thread = nil
      end

      # Schedule a deferred upload that waits for app boot to complete.
      #
      # In Rails: registers ActiveSupport.on_load(:after_initialize). When the
      # hook has already fired (e.g., this Component was built by a reconfigure
      # after Rails finished initializing), the callback runs immediately.
      #
      # In non-Rails: triggers start_upload immediately.
      #
      # Each Component registers its own callback. Old Components that have
      # been shut down short-circuit in start_upload via @shutdown.
      # Cross-process deduplication is handled by the class-level
      # uploaded_this_process? flag, not by guarding registration.
      #
      # @return [void]
      def schedule_deferred_upload
        if defined?(::ActiveSupport) && defined?(::Rails::Railtie)
          # Capture self — on_load runs the block via instance_exec on the
          # loaded object (Rails::Application), so a bare `start_upload`
          # would resolve against it.
          component = self
          logger = @logger
          ::ActiveSupport.on_load(:after_initialize) do
            # Only auto-trigger when Rails has eager-loaded application
            # classes during initialization. In dev (eager_load=false)
            # there is nothing complete to extract; the auto-deferred
            # upload would race with explicit triggers and produce
            # under-extracted uploads.
            if defined?(::Rails) && ::Rails.application&.config&.eager_load
              component.start_upload
            else
              logger.debug { "symdb: skipping auto-deferred upload (eager_load disabled)" }
            end
          end
        else
          start_upload
        end
      end

      # Whether this component has been shut down.
      # @return [Boolean]
      def shutdown?
        @mutex.synchronize { @shutdown }
      end

      # Schedule symbol upload (triggered by remote config or force mode).
      # The actual extraction is debounced by EXTRACT_DEBOUNCE_INTERVAL seconds —
      # subsequent calls within the window restart the timer.
      # Thread-safe: can be called concurrently from multiple remote config updates.
      # @return [void]
      def start_upload
        return if Component.uploaded_this_process?

        @scheduler_mutex.synchronize do
          return if @shutdown

          @scheduled_at = Datadog::Core::Utils::Time.get_time + EXTRACT_DEBOUNCE_INTERVAL
          @scheduler_signaled = true
          @scheduler_cv.signal
          ensure_scheduler_thread
        end
      rescue => e
        @logger.debug { "symdb: error scheduling upload: #{e.class}: #{e}" }
      end

      # Stop symbol upload (cancel the scheduler).
      # Thread-safe: can be called concurrently from multiple remote config updates.
      # @return [void]
      def stop_upload
        @scheduler_mutex.synchronize do
          @scheduled_at = nil
          @scheduler_signaled = true
          @scheduler_cv.signal
        end
      end

      # Block until any Component in this process has finished an extract+upload,
      # or until the timeout elapses. Used by short-lived scripts that trigger
      # an upload via force_upload and need to wait before exiting.
      # @param timeout [Numeric] Maximum seconds to wait
      # @return [Boolean] true if an upload completed; false on timeout
      def wait_for_idle(timeout: 30)
        deadline = Datadog::Core::Utils::Time.get_time + timeout
        Component.upload_done_mutex.synchronize do
          until Component.send(:instance_variable_get, :@uploaded_this_process)
            remaining = deadline - Datadog::Core::Utils::Time.get_time
            return false if remaining <= 0
            Component.upload_done_cv.wait(Component.upload_done_mutex, remaining)
          end
        end
        true
      end

      # Shutdown component and cleanup resources.
      # Cancels the per-instance scheduler so any pending debounced extraction
      # is dropped. Waits for an in-flight extraction to complete before
      # returning. Does not touch class-level state, so a sibling Component
      # built after shutdown can still upload.
      # @return [void]
      def shutdown!
        @scheduler_mutex.synchronize do
          @shutdown = true
          @scheduler_signaled = true
          @scheduler_cv.signal
        end
        @scheduler_thread&.join(5)
        @scheduler_thread = nil

        @mutex.synchronize do
          @shutdown = true
          if @upload_in_progress
            @upload_in_progress_cv.wait(@mutex, 5)
          end
        end

        @scope_batcher.shutdown
      end

      # @api private
      private

      # Check whether the runtime environment supports symbol database upload.
      # Only MRI Ruby 2.6+ is supported. JRuby and TruffleRuby are not supported
      # because ObjectSpace iteration and Method#source_location behave differently.
      # Configuration accessors remain available on all platforms — this only gates
      # the component (upload) itself.
      # @param logger [Logger]
      # @return [Boolean]
      def self.environment_supported?(logger)
        if RUBY_ENGINE != 'ruby'
          logger.debug { "symdb: not supported on #{RUBY_ENGINE}, skipping" }
          return false
        end
        if RUBY_VERSION < '2.6'
          logger.debug { "symdb: requires Ruby 2.6+, running #{RUBY_VERSION}, skipping" }
          return false
        end
        true
      end
      private_class_method :environment_supported?

      # Start the scheduler thread if not already running.
      # Must be called from within @scheduler_mutex.synchronize.
      # @return [void]
      def ensure_scheduler_thread
        return if @scheduler_thread&.alive?
        @scheduler_thread = Thread.new { scheduler_loop }
      end

      # Scheduler thread main loop. Waits for the debounce window to elapse,
      # then runs extract_and_upload exactly once for this Component.
      # @return [void]
      def scheduler_loop
        loop do
          @scheduler_mutex.synchronize do
            return if @shutdown
            return if Component.uploaded_this_process?

            if @scheduled_at.nil?
              # Nothing scheduled (e.g. stop_upload cleared it). Wait
              # indefinitely for a signal, then re-evaluate.
              @scheduler_signaled = false
              @scheduler_cv.wait(@scheduler_mutex)
              next
            end

            remaining = @scheduled_at - Datadog::Core::Utils::Time.get_time
            if remaining > 0
              # Wait until the debounce deadline. Any signal (start_upload,
              # stop_upload, shutdown!) wakes us early; we always re-loop
              # and recompute rather than firing immediately on wake.
              @scheduler_signaled = false
              @scheduler_cv.wait(@scheduler_mutex, remaining)
              next
            end

            # Deadline elapsed without further signal — fall through and fire.
          end

          # Outside the mutex.
          return if @shutdown
          if Component.uploaded_this_process?
            return
          end

          extract_and_upload
          Component.mark_uploaded
          return
        end
      rescue => e
        @logger.debug { "symdb: scheduler error: #{e.class}: #{e}" }
      end

      # Extract symbols from all loaded modules and upload.
      # @return [void]
      def extract_and_upload
        @mutex.synchronize { @upload_in_progress = true }

        begin
          @logger.trace { "symdb: starting extraction and upload" }
          start_time = Datadog::Core::Utils::Time.get_time

          # Extract symbols from all loaded modules grouped by source file.
          # extract_all handles ObjectSpace iteration, filtering, and FQN-based nesting.
          file_scopes = @extractor.extract_all
          extracted_count = 0
          file_scopes.each do |scope|
            @scope_batcher.add_scope(scope)
            extracted_count += 1
            log_scope_tree(scope, 0)
          end

          extraction_duration = Datadog::Core::Utils::Time.get_time - start_time
          injectable_count = count_injectable_methods(file_scopes)
          @logger.debug { "symdb: extracted #{extracted_count} scopes (#{injectable_count} methods with injectable lines) in #{'%.2f' % extraction_duration}s" }

          # Flush any remaining scopes (triggers upload)
          @scope_batcher.flush

          @last_upload_time = Datadog::Core::Utils::Time.now
        rescue => e
          @logger.debug { "symdb: extraction error: #{e.class}: #{e}" }
        ensure
          @mutex.synchronize do
            @upload_in_progress = false
            @upload_in_progress_cv.signal
          end
        end
      end

      def log_scope_tree(scope, depth)
        indent = '  ' * depth
        @logger.trace { "symdb:   #{indent}#{scope.scope_type} #{scope.name}" }
        scope.scopes&.each { |child| log_scope_tree(child, depth + 1) }
      end

      def count_injectable_methods(file_scopes)
        count = 0
        file_scopes.each do |file_scope|
          file_scope.scopes&.each do |class_or_module|
            class_or_module.scopes&.each do |method_scope|
              count += 1 if method_scope.scope_type == 'METHOD' && method_scope.targetable_lines?
            end
          end
        end
        count
      end
    end
  end
end
