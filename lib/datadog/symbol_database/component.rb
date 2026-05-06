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
    # - Hot-load coverage: TracePoint :class hook captures classes loaded after
    #   initial extraction, enqueues them on a per-instance buffer; the scheduler
    #   drains the buffer on debounce and extracts each one via Extractor#extract,
    #   matching Java/Python/.NET continuous coverage.
    #
    # Upload flow:
    # 1. Remote config sends upload_symbols: true (or force_upload mode)
    # 2. start_upload called — schedules extraction EXTRACT_DEBOUNCE_INTERVAL
    #    seconds in the future on a per-instance scheduler thread, and lazily
    #    installs the TracePoint :class hook if not already installed.
    # 3. When the timer fires (no further start_upload calls reset it),
    #    extract_and_upload runs. On the first call: ObjectSpace iteration →
    #    Extractor#extract_all. On subsequent calls: drain the hot-load buffer →
    #    Extractor#extract per module.
    # 4. ScopeBatcher batches and triggers Uploader.
    # 5. As new classes load throughout the process lifetime, the TracePoint hook
    #    fires and signals the scheduler — the next debounce window produces an
    #    incremental upload of just the new classes.
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

      attr_reader :settings, :last_upload_time, :last_upload_scope_count, :upload_in_progress

      # Initialize component.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      def initialize(settings, agent_settings, logger)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger

        @extractor = Extractor.new(logger: logger, settings: settings)
        @uploader = Uploader.new(settings: settings, agent_settings: agent_settings, logger: logger)
        @scope_batcher = ScopeBatcher.new(@uploader, logger: logger)

        @last_upload_time = nil
        @last_upload_scope_count = nil
        @mutex = Mutex.new
        @upload_in_progress = false
        @upload_in_progress_cv = ConditionVariable.new
        @shutdown = false

        # Signalled when @last_upload_time advances. wait_for_idle blocks on this
        # so short-lived scripts (e.g. gobo's bin/extract_symbols) can wait for
        # an upload attempt to complete without depending on a one-shot flag.
        @last_upload_time_cv = ConditionVariable.new

        # Per-instance scheduler state. The scheduler thread is started lazily
        # on the first start_upload call.
        @scheduler_mutex = Mutex.new
        @scheduler_cv = ConditionVariable.new
        @scheduled_at = nil
        @scheduler_signaled = false
        @scheduler_thread = nil

        # Hot-load coverage state. TracePoint :class hook is installed lazily on
        # the first start_upload call; classes defined after that point are
        # enqueued here and drained by the scheduler on debounce. Distinguishes
        # initial extraction (extract_all) from incremental (per-module extract).
        @hot_load_buffer = []
        @hot_load_buffer_mutex = Mutex.new
        @hot_load_tracepoint = nil
        @initial_extraction_done = false
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
      # been shut down short-circuit in start_upload via @shutdown. The hot-load
      # hook handles classes loaded after this initial trigger, so under
      # eager_load=false an under-extracted initial upload self-corrects as the
      # app exercises code.
      #
      # @return [void]
      def schedule_deferred_upload
        if defined?(::ActiveSupport) && defined?(::Rails::Railtie)
          # Capture self — on_load runs the block via instance_exec on the
          # loaded object (Rails::Application), so a bare `start_upload`
          # would resolve against it.
          component = self
          ::ActiveSupport.on_load(:after_initialize) do
            component.start_upload
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
        @scheduler_mutex.synchronize do
          return if @shutdown

          install_hot_load_hook
          @scheduled_at = Datadog::Core::Utils::Time.get_time + EXTRACT_DEBOUNCE_INTERVAL
          @scheduler_signaled = true
          @scheduler_cv.signal
          ensure_scheduler_thread
        end
      rescue => e
        @logger.debug { "symdb: error scheduling upload: #{e.class}: #{e.message}" }
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

      # Block until this Component finishes an extract+upload after this call,
      # or until the timeout elapses. Used by short-lived scripts that trigger
      # an upload via force_upload and need to wait before exiting.
      # Tracks @last_upload_time advance — returns true once any upload attempt
      # completes (success or failure), false on timeout.
      # @param timeout [Numeric] Maximum seconds to wait
      # @return [Boolean] true if an upload completed; false on timeout
      def wait_for_idle(timeout: 30)
        deadline = Datadog::Core::Utils::Time.get_time + timeout
        @mutex.synchronize do
          start_time = @last_upload_time
          while @last_upload_time == start_time
            remaining = deadline - Datadog::Core::Utils::Time.get_time
            return false if remaining <= 0
            @last_upload_time_cv.wait(@mutex, remaining)
          end
        end
        true
      end

      # Shutdown component and cleanup resources.
      # Disables the hot-load TracePoint so no events queue for a dead
      # scheduler. Cancels the per-instance scheduler so any pending debounced
      # extraction is dropped. Waits for an in-flight extraction to complete
      # before returning. Does not touch any sibling Components, so a sibling
      # Component built after shutdown can still upload.
      # @return [void]
      def shutdown!
        @hot_load_tracepoint&.disable
        @hot_load_tracepoint = nil

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
      # then runs extract_and_upload. Loops indefinitely so that hot-load
      # signals fired after the initial upload trigger subsequent incremental
      # uploads.
      # @return [void]
      def scheduler_loop
        loop do
          should_fire = false

          # steep:ignore:start
          @scheduler_mutex.synchronize do
            return if @shutdown

            if @scheduled_at.nil?
              # Nothing scheduled (e.g. stop_upload cleared it, or no hot-load
              # events since the last upload). Wait indefinitely for a signal,
              # then re-evaluate on next loop.
              @scheduler_signaled = false
              @scheduler_cv.wait(@scheduler_mutex)
            else
              remaining = @scheduled_at - Datadog::Core::Utils::Time.get_time
              if remaining > 0
                # Wait until the debounce deadline. Any signal (start_upload,
                # stop_upload, shutdown!, hot-load event) wakes us early; we
                # always re-loop and recompute rather than firing immediately
                # on wake.
                @scheduler_signaled = false
                @scheduler_cv.wait(@scheduler_mutex, remaining)
              else
                # Deadline elapsed without further signal — fire after releasing
                # the mutex. Clear @scheduled_at so the next loop iteration
                # waits for the next start_upload or hot-load signal.
                should_fire = true
                @scheduled_at = nil
              end
            end
          end
          # steep:ignore:end

          # `next` inside `synchronize` only exits the synchronize block — not the
          # surrounding loop. Use an explicit flag so the loop only fires
          # extract_and_upload when the debounce deadline has actually elapsed.
          next unless should_fire

          # Outside the mutex.
          return if @shutdown

          extract_and_upload
        end
      rescue => e
        @logger.debug { "symdb: scheduler error: #{e.class}: #{e.message}" }
      end

      # Extract symbols and upload. First call runs extract_all (full ObjectSpace
      # walk); subsequent calls drain the hot-load buffer and extract just the
      # newly-loaded modules via Extractor#extract.
      # @return [void]
      def extract_and_upload
        @mutex.synchronize { @upload_in_progress = true }

        begin
          @logger.trace { "symdb: starting extraction and upload" }
          start_time = Datadog::Core::Utils::Time.get_time

          if @initial_extraction_done
            file_scopes = extract_hot_load_buffer
            mode_label = "hot-load"
          else
            # Discard any TracePoint events captured between hook install and
            # this initial scan — extract_all walks ObjectSpace which already
            # covers everything loaded at this moment. Anything loaded during
            # or after extract_all stays buffered for the next drain.
            @hot_load_buffer_mutex.synchronize { @hot_load_buffer.clear }
            # extract_all handles ObjectSpace iteration, filtering, and FQN-based nesting.
            file_scopes = @extractor.extract_all
            @initial_extraction_done = true
            mode_label = "initial"
          end

          extracted_count = 0
          file_scopes.each do |scope|
            @scope_batcher.add_scope(scope)
            extracted_count += 1
            log_scope_tree(scope, 0)
          end

          extraction_duration = Datadog::Core::Utils::Time.get_time - start_time
          targetable_count = count_targetable_methods(file_scopes)
          @logger.debug { "symdb: #{mode_label} extracted #{extracted_count} scopes (#{targetable_count} methods with targetable lines) in #{'%.2f' % extraction_duration}s" }

          # Flush any remaining scopes (triggers upload)
          @scope_batcher.flush

          @mutex.synchronize do
            @last_upload_time = Datadog::Core::Utils::Time.now
            @last_upload_scope_count = extracted_count
            @last_upload_time_cv.broadcast
          end
        rescue => e
          @logger.debug { "symdb: extraction error: #{e.class}: #{e.message}" }
          @mutex.synchronize do
            @last_upload_time = Datadog::Core::Utils::Time.now
            @last_upload_time_cv.broadcast
          end
        ensure
          @mutex.synchronize do
            @upload_in_progress = false
            @upload_in_progress_cv.signal
          end
        end
      end

      # Drain the hot-load buffer, dedup by object_id, return the array of
      # FILE scopes from per-module extraction.
      # @return [Array<Scope>]
      def extract_hot_load_buffer
        modules = @hot_load_buffer_mutex.synchronize { @hot_load_buffer.shift(@hot_load_buffer.length) }
        return [] if modules.empty?

        seen = {}
        modules.each { |mod| seen[mod.object_id] = mod }
        seen.values.map { |mod| @extractor.extract(mod) }.compact
      end

      # Install the TracePoint :class hook (lazy — only on first start_upload).
      # Hook fires for every class/module body open including reopens; pushes
      # the module onto @hot_load_buffer and signals the scheduler. Singleton
      # classes are filtered for the same reason as in Extractor#extract_all.
      # Must be called from within @scheduler_mutex.synchronize.
      # @return [void]
      def install_hot_load_hook
        return if @hot_load_tracepoint
        component = self
        @hot_load_tracepoint = TracePoint.new(:class) do |tp|
          mod = tp.self
          # steep:ignore:start
          next if mod.singleton_class?
          component.send(:enqueue_hot_load, mod)
          # steep:ignore:end
        end
        @hot_load_tracepoint.enable
      end

      # Enqueue a hot-loaded module and signal the scheduler.
      # Called from the TracePoint :class block — must be cheap.
      # @param mod [Module]
      # @return [void]
      def enqueue_hot_load(mod)
        @hot_load_buffer_mutex.synchronize { @hot_load_buffer << mod }
        @scheduler_mutex.synchronize do
          return if @shutdown
          @scheduled_at = Datadog::Core::Utils::Time.get_time + EXTRACT_DEBOUNCE_INTERVAL
          @scheduler_signaled = true
          @scheduler_cv.signal
        end
      end

      def log_scope_tree(scope, depth)
        indent = '  ' * depth
        @logger.trace { "symdb:   #{indent}#{scope.scope_type} #{scope.name}" }
        scope.scopes&.each { |child| log_scope_tree(child, depth + 1) }
      end

      def count_targetable_methods(file_scopes)
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
