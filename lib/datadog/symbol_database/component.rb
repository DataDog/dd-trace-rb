# frozen_string_literal: true

require_relative "../symbol_database"
require_relative "extractor"
require_relative "logger"
require_relative "scope_batcher"
require_relative "uploader"
require_relative "../core/utils/time"
require_relative "../di/fatal_exceptions"

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

      # Cached unbound Module#singleton_class? — dispatched explicitly inside the
      # hot-load TracePoint so user code that overrides `singleton_class?` (e.g.
      # `def self.singleton_class?(arg)`) cannot raise inside the :class hook and
      # abort the user's class definition. Mirrors the cache in Extractor.
      MODULE_SINGLETON_CLASS_PRED = Module.instance_method(:singleton_class?)
      private_constant :MODULE_SINGLETON_CLASS_PRED

      # Build a new Component if the runtime supports it and dependencies are met.
      # The caller (Core::Configuration::Components) decides whether the feature is
      # enabled and only invokes build when it is, so a disabled component is never
      # constructed. This method gates only on symbol database's own requirements
      # (supported platform, remote config availability).
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      # @param telemetry [Core::Telemetry::Component, nil] Telemetry component for error reporting
      # @param di_active [Proc, nil] Predicate returning whether Dynamic
      #   Instrumentation is currently active (started). Gates remote-config
      #   uploads in the nil-default case; nil means "no gate" (standalone
      #   force_upload contexts).
      # @return [Component, nil] Component instance or nil if requirements not met
      def self.build(settings, agent_settings, logger, telemetry: nil, di_active: nil)
        symdb_logger = SymbolDatabase::Logger.new(settings, logger)

        # Symbol database requires MRI Ruby 2.7+.
        # Configuration accessors (settings.symbol_database.*) remain available on all
        # platforms — only the component (upload) is disabled on unsupported engines/versions.
        # environment_supported? logs the specific reason (engine or version) internally.
        return nil unless environment_supported?(symdb_logger)

        # Requires remote config (unless force mode)
        if !settings.remote&.enabled && !settings.symbol_database.internal.force_upload
          symdb_logger.debug("symdb: remote config not available and force_upload not set, skipping")
          return nil
        end

        new(settings, agent_settings, symdb_logger, telemetry: telemetry, di_active: di_active).tap do |component|
          # Defer extraction if force upload mode — wait for app boot to complete
          component.schedule_deferred_upload if settings.symbol_database.internal.force_upload
        end
      end

      attr_reader :settings, :logger, :last_upload_time, :last_upload_scope_count, :upload_in_progress

      # Initialize component.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      # @param telemetry [Core::Telemetry::Component, nil] Telemetry component for error reporting
      # @param di_active [Proc, nil] Predicate returning whether Dynamic Instrumentation is currently active
      def initialize(settings, agent_settings, logger, telemetry: nil, di_active: nil)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
        @telemetry = telemetry
        @di_active = di_active

        @extractor = Extractor.new(logger: logger, settings: settings)
        @uploader = Uploader.new(settings: settings, agent_settings: agent_settings, logger: logger, telemetry: telemetry)
        @scope_batcher = ScopeBatcher.new(@uploader, logger: logger)

        @last_upload_time = nil
        @last_upload_scope_count = nil
        @mutex = Mutex.new
        @upload_in_progress = false
        @upload_in_progress_cv = ConditionVariable.new
        @shutdown = false
        # PID at construction time. Compared against Process.pid in shutdown!
        # to detect forked-child callers, whose inherited @upload_in_progress
        # snapshot is stale: the scheduler thread that would clear it lives
        # only in the parent. See shutdown! for details.
        @owner_pid = Process.pid

        # Signalled when @last_upload_time advances. wait_for_idle blocks on this
        # so short-lived scripts that trigger an upload can wait for an upload
        # attempt to complete without depending on a one-shot flag.
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

        # Sticky record of "remote config (or force mode) wants symbols
        # uploaded", independent of whether DI is currently active. Set when an
        # upload is requested and either allowed or deferred by the DI gate;
        # cleared only when RC explicitly disables uploads (stop_upload). It
        # survives stop_for_di_disable's scheduler teardown, so
        # resume_pending_upload can restart uploads after a DI disable->re-enable
        # cycle even though RC does not re-dispatch the unchanged symbol-database
        # config.
        @upload_requested = false
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
        @scheduler_mutex.synchronize { @shutdown }
      end

      # Schedule symbol upload (triggered by remote config or force mode).
      # The actual extraction is debounced by EXTRACT_DEBOUNCE_INTERVAL seconds —
      # subsequent calls within the window restart the timer.
      # Thread-safe: can be called concurrently from multiple remote config updates.
      # @return [void]
      def start_upload
        @scheduler_mutex.synchronize do
          return if @shutdown

          unless upload_allowed?
            if deferred_by_di_gate?
              # nil-default case: Symbol Database mirrors Dynamic Instrumentation
              # and DI is not active. Record the desire and defer; resume_pending_upload
              # re-attempts when DI is enabled. Without this gate the tracer would
              # extract and upload symbols for applications that never enabled DI.
              @upload_requested = true
              @logger.debug("symdb: upload requested but Dynamic Instrumentation is not active; deferring until DI is enabled")
            else
              # Explicit symbol_database.enabled = false: the feature is disabled,
              # not merely waiting on DI. Clear the desire so resume_pending_upload
              # does not retry a disabled feature.
              @upload_requested = false
              @logger.debug("symdb: upload requested but symbol database upload is disabled; skipping")
            end
            return
          end
          @upload_requested = true

          if @owner_pid != Process.pid
            # Forked child: claim ownership and clear inherited
            # @upload_in_progress. The inherited flag was the parent's
            # snapshot; the parent's scheduler thread does not exist in this
            # process. Any upload starting now is child-owned and must be
            # waited on in shutdown! via the PID-match branch.
            @owner_pid = Process.pid
            @mutex.synchronize { @upload_in_progress = false }
          end

          install_hot_load_hook
          @scheduled_at = Datadog::Core::Utils::Time.get_time + EXTRACT_DEBOUNCE_INTERVAL
          @scheduler_signaled = true
          @scheduler_cv.signal
          ensure_scheduler_thread
        end
      rescue Exception => e # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(e)
        @logger.debug { "symdb: error scheduling upload: #{e.class}: #{e.message}" }
        @telemetry&.report(e, description: "symdb: error scheduling upload")
      end

      # Stop symbol upload in response to remote config sending
      # upload_symbols: false or deleting the config: the customer no longer wants
      # uploads, so clear the sticky @upload_requested desire (a later
      # resume_pending_upload must not restart it) and tear down the scheduler and
      # hot-load hook.
      # Thread-safe: can be called concurrently from multiple remote config updates.
      # @return [void]
      def stop_upload
        @scheduler_mutex.synchronize { @upload_requested = false }
        suspend_scheduling
      end

      # Re-attempt a symbol upload that remote config requested but that is not
      # currently running because Dynamic Instrumentation was inactive — either
      # deferred at request time, or suspended by stop_for_di_disable when DI was
      # turned off. Called from the orchestration layer (Tracing::Remote) when DI
      # is enabled via remote configuration (implicit enablement). No-op unless an
      # upload was requested and not since disabled. Mirrors DI's
      # replay_current_probes: RC does not re-dispatch the unchanged
      # symbol-database config on DI re-enable, so the tracer restarts the upload
      # from its own retained desire.
      # @return [void]
      def resume_pending_upload
        requested = @scheduler_mutex.synchronize { @upload_requested }
        start_upload if requested
        nil
      end

      # Stop uploading when Dynamic Instrumentation is disabled via remote
      # configuration. Only the nil-default (follows-DI) case stops; an explicit
      # symbol_database.enabled = true and force_upload are independent of DI and
      # keep running. Called from the orchestration layer (Tracing::Remote) so
      # Symbol Database's TracePoint and scheduler don't keep uploading after DI
      # is turned off. No-op if uploads were never started.
      # @return [void]
      def stop_for_di_disable
        return if @settings.symbol_database.internal.force_upload
        return unless @settings.symbol_database.enabled.nil?

        # Suspend, don't stop: preserve @upload_requested so resume_pending_upload
        # restarts the upload when DI is re-enabled and RC never re-sends the
        # (unchanged) symbol-database config.
        suspend_scheduling
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
      # The TracePoint teardown sits inside the same @scheduler_mutex critical
      # section as the @shutdown flag flip, so it is atomic against a concurrent
      # start_upload (which installs the TracePoint under @scheduler_mutex). Without
      # that, a shutdown interleaved with a start could leave an enabled TracePoint
      # rooted by the VM — class loads would keep growing @hot_load_buffer for the
      # rest of the process lifetime (enqueue_hot_load's @shutdown check skips
      # re-scheduling but only after the buffer push).
      # @return [void]
      def shutdown!
        @scheduler_mutex.synchronize do
          @hot_load_tracepoint&.disable
          @hot_load_tracepoint = nil
          @shutdown = true
          @scheduler_signaled = true
          @scheduler_cv.signal
        end
        @scheduler_thread&.join(5)
        @scheduler_thread = nil

        @mutex.synchronize do
          if @upload_in_progress
            if Process.pid == @owner_pid
              @upload_in_progress_cv.wait(@mutex, 5)
            else
              # We are in a forked child that inherited this Component but
              # never called start_upload here. The scheduler thread (the
              # only writer that clears @upload_in_progress and signals the
              # cv) lives only in the parent — fork carries only the calling
              # thread, so nothing in this process can ever signal us.
              # Waiting would burn the full 5s timeout for no benefit. Treat
              # the inherited @upload_in_progress as a stale snapshot and
              # proceed; the parent's shutdown! (running in the parent) is
              # authoritative. Child-owned uploads (where start_upload was
              # called in this process) take the PID-match branch above,
              # because start_upload claims @owner_pid for the current
              # process.
              @upload_in_progress = false
            end
          end
        end

        @scope_batcher.shutdown
      end

      # Reinitialize per-instance state in a forked child process.
      #
      # `Process.fork` copies the parent's memory but only the forking thread
      # survives in the child. Background threads (`@scheduler_thread`) are
      # dead, mutexes and condition variables are copied without owner
      # tracking (orphan-lock risk if the parent held a mutex at the fork
      # instant), and the TracePoint hook is bound to the dead scheduler.
      #
      # State reset (the child does its own initial extraction, then hot-load
      # continues from there):
      # - Hot-load buffer cleared — the child will rediscover via extract_all.
      # - `@initial_extraction_done = false` — child has not extracted yet.
      # - `@hot_load_tracepoint = nil` — `start_upload` reinstalls a fresh one
      #   bound to the child's component.
      # - `@scheduler_thread = nil`, `@scheduled_at = nil`,
      #   `@scheduler_signaled = false` — scheduler restarts on next
      #   `start_upload`.
      # - `@upload_in_progress = false` — parent may have been mid-upload at
      #   the fork instant; the child has no upload in flight.
      # - `@scope_batcher` replaced with a fresh instance. The inherited batcher
      #   carries the parent's `@uploaded_modules` set, which `add_scope` uses
      #   to dedup by scope name. Without a fresh batcher, the child's
      #   re-extraction silently drops every scope whose name the parent
      #   already uploaded — under `preload_app!` that's most of the app.
      #
      # Mutex/CV reinit (orphan-lock guard):
      # - `@scheduler_mutex`, `@scheduler_cv`, `@mutex`,
      #   `@upload_in_progress_cv`, `@last_upload_time_cv`,
      #   `@hot_load_buffer_mutex`.
      #
      # Force-upload mode: the parent's scheduled extraction is dead in the
      # child, so re-register the deferred-upload callback. In Rails the
      # `:after_initialize` hook has already fired (initialization happened
      # in the parent), so the on_load block runs immediately and the child
      # schedules its own upload. In non-Rails, this calls `start_upload`
      # directly.
      #
      # Cross-process upload deduplication is intentionally not handled here.
      # Each forked Component does its own initial extraction. Workers in
      # `preload_app! + eager_load=true` deployments hold identical code to
      # the parent — backend dedup of identical-content uploads is the
      # backend's responsibility, not the tracer's.
      #
      # @return [void]
      def after_fork!
        # Disable the inherited TracePoint before dropping the reference: fork
        # copies the enabled TP into the child, where it remains rooted by the
        # VM. Without an explicit disable, every subsequent class load in the
        # child would enqueue through the inherited hook in addition to the
        # fresh hook that start_upload installs.
        @hot_load_tracepoint&.disable
        @hot_load_buffer = []
        @hot_load_buffer_mutex = Mutex.new
        @hot_load_tracepoint = nil
        @initial_extraction_done = false

        @scheduler_mutex = Mutex.new
        @scheduler_cv = ConditionVariable.new
        @scheduled_at = nil
        @scheduler_signaled = false
        @scheduler_thread = nil

        @mutex = Mutex.new
        @upload_in_progress = false
        @upload_in_progress_cv = ConditionVariable.new
        @last_upload_time_cv = ConditionVariable.new

        # Fresh ScopeBatcher: the inherited one carries the parent's
        # @uploaded_modules set, against which add_scope dedups by name.
        @scope_batcher = ScopeBatcher.new(@uploader, logger: @logger)

        schedule_deferred_upload if @settings.symbol_database.internal.force_upload
      end

      private

      # Tear down the scheduler and hot-load hook without clearing the sticky
      # @upload_requested desire, so resume_pending_upload can restart uploads
      # that RC still wants. Disables the TracePoint :class hook so post-stop
      # class loads don't re-arm the scheduler, clears the hot-load buffer, and
      # resets @initial_extraction_done so a future resume performs a fresh
      # extract_all instead of draining an empty buffer.
      # The TracePoint teardown sits inside the same @scheduler_mutex critical
      # section as the @scheduled_at reset, so it is atomic against a concurrent
      # start_upload (which installs the TracePoint under @scheduler_mutex). Without
      # that, a stop interleaved with a start could leave an enabled TracePoint
      # rooted by the VM after this returned.
      # @return [void]
      def suspend_scheduling
        @scheduler_mutex.synchronize do
          @hot_load_tracepoint&.disable
          @hot_load_tracepoint = nil
          @scheduled_at = nil
          @scheduler_signaled = true
          @scheduler_cv.signal
        end
        @hot_load_buffer_mutex.synchronize { @hot_load_buffer.clear }
        @initial_extraction_done = false
        nil
      end

      # Whether a remote-config-triggered upload may proceed now.
      #
      # force_upload and an explicit `symbol_database.enabled = true` both mean
      # "upload regardless of Dynamic Instrumentation". Only the nil-default case
      # — where Symbol Database mirrors DI — is gated on DI actually being active,
      # so the tracer never extracts symbols for an application that never
      # enabled Dynamic Instrumentation.
      # @return [bool]
      def upload_allowed?
        return true if @settings.symbol_database.internal.force_upload

        case @settings.symbol_database.enabled
        when true then true
        when false then false
        # steep:ignore NoMethod — Steep does not narrow @di_active to non-nil after the .nil? check
        else @di_active.nil? || @di_active.call # steep:ignore NoMethod
        end
      end

      # Whether upload is currently blocked specifically by the nil-default
      # DI-active gate — the only case that defers and retries via
      # resume_pending_upload. An explicit symbol_database.enabled = false is a
      # disabled feature, not a deferral, so it clears @upload_requested and is
      # not retried. force_upload and explicit true are never gated, so they are
      # never deferred.
      # @return [bool]
      def deferred_by_di_gate?
        return false if @settings.symbol_database.internal.force_upload
        return false unless @settings.symbol_database.enabled.nil?

        # After the guards above, upload_allowed? reduces to the DI-active gate,
        # so a disallowed upload here is precisely a DI-gate deferral.
        !upload_allowed?
      end

      # Check whether the runtime environment supports symbol database upload,
      # logging the reason when it does not.
      # @param logger [Logger]
      # @return [Boolean]
      def self.environment_supported?(logger)
        return true if SymbolDatabase.supported_runtime?

        if RUBY_ENGINE != "ruby"
          logger.debug { "symdb: not supported on #{RUBY_ENGINE}, skipping" }
        else
          logger.debug { "symdb: requires Ruby 2.7+, running #{RUBY_VERSION}, skipping" }
        end
        false
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
          # should_fire = true means the debounce deadline elapsed without further
          # signals; extract_and_upload runs once after the mutex is released.
          should_fire = false

          @scheduler_mutex.synchronize do
            return if @shutdown

            # Copy to local so Steep narrows `Float?` to `Float` in the else branch.
            # Steep does not track narrowing on instance variables across nil checks.
            scheduled_at = @scheduled_at
            if scheduled_at.nil?
              # Nothing scheduled (e.g. stop_upload cleared it, or no hot-load
              # events since the last upload). Wait indefinitely for a signal,
              # then re-evaluate on next loop.
              @scheduler_signaled = false
              @scheduler_cv.wait(@scheduler_mutex)
            else
              remaining = scheduled_at - Datadog::Core::Utils::Time.get_time
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

          # `next` inside `synchronize` only exits the synchronize block — not the
          # surrounding loop. Use an explicit flag so the loop only fires
          # extract_and_upload when the debounce deadline has actually elapsed.
          next unless should_fire

          # Outside the mutex.
          return if @shutdown

          extract_and_upload
        end
      rescue Exception => e # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(e)
        @logger.debug { "symdb: scheduler error: #{e.class}: #{e.message}" }
        @telemetry&.report(e, description: "symdb: scheduler error")
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

          extracted_count = 0
          targetable_count = 0
          consume = lambda do |scope|
            @scope_batcher.add_scope(scope)
            extracted_count += 1
            targetable_count += count_targetable_methods_in_scope(scope)
            log_scope_tree(scope, 0)
          end

          if @initial_extraction_done
            extract_hot_load_buffer.each(&consume)
            mode_label = "hot-load"
          else
            # Discard any TracePoint events captured between hook install and
            # this initial scan — extract_all walks ObjectSpace which already
            # covers everything loaded at this moment. Anything loaded during
            # or after extract_all stays buffered for the next drain.
            @hot_load_buffer_mutex.synchronize { @hot_load_buffer.clear }
            # Stream form of extract_all yields one FILE scope at a time and frees
            # the per-file intermediate tree as it goes — the full Array<Scope> is
            # never materialized, keeping peak memory bounded for large workspaces.
            @extractor.extract_all(&consume)
            @initial_extraction_done = true
            mode_label = "initial"
          end

          extraction_duration = Datadog::Core::Utils::Time.get_time - start_time
          @logger.debug { "symdb: #{mode_label} extracted #{extracted_count} scopes (#{targetable_count} methods with targetable lines) in #{"%.2f" % extraction_duration}s" }

          # Flush any remaining scopes (triggers upload)
          @scope_batcher.flush

          @mutex.synchronize do
            @last_upload_time = Datadog::Core::Utils::Time.now
            @last_upload_scope_count = extracted_count
            @last_upload_time_cv.broadcast
          end
        rescue Exception => e # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(e)
          @logger.debug { "symdb: extraction error: #{e.class}: #{e.message}" }
          @telemetry&.report(e, description: "symdb: extraction error")
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
        logger = @logger
        telemetry = @telemetry
        @hot_load_tracepoint = TracePoint.new(:class) do |tp|
          # The :class TracePoint fires inside the customer's class body —
          # any exception that escapes this block surfaces at the customer's
          # `class Foo; ... end` line and breaks their class load. The
          # MODULE_SINGLETON_CLASS_PRED dispatch defends against one specific
          # raise source (user-overridden singleton_class?); this rescue
          # closes the general case. Verified: a raise inside the callback
          # backtraces through `<class:CustomerClass>` in Ruby 3.x.

          mod = tp.self
          next if MODULE_SINGLETON_CLASS_PRED.bind(mod).call
          component.send(:enqueue_hot_load, mod)
        rescue Exception => e # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(e)
          # Logger or telemetry can themselves raise (custom logger
          # implementation, telemetry worker in an unexpected state). The
          # :class TracePoint fires inside customer class bodies, so the
          # error boundary must hold even when error reporting fails;
          # nothing useful to do if logging is broken.
          begin
            logger.debug { "symdb: hot-load hook error: #{e.class}: #{e.message}" }
            telemetry&.report(e, description: "symdb: hot-load hook error")
          rescue Exception => report_exc # standard:disable Lint/RescueException
            Datadog::DI.reraise_if_fatal(report_exc)
            nil
          end
        end
        @hot_load_tracepoint.enable # steep:ignore NoMethod
      end

      # Enqueue a hot-loaded module and signal the scheduler.
      # Called from the TracePoint :class block — must be cheap.
      # @param mod [Module]
      # @return [void]
      def enqueue_hot_load(mod)
        @hot_load_buffer_mutex.synchronize { @hot_load_buffer << mod }
        @scheduler_mutex.synchronize do
          return if @shutdown
          # TracePoint#disable does not wait for in-flight callbacks: a :class
          # event firing concurrently with stop_upload can reach here after the
          # hook has been torn down. Without this guard the stale event would
          # re-arm the scheduler, contradicting stop_upload's contract. The
          # buffer push above is harmless — the next start_upload runs
          # extract_all, which clears the buffer before extracting.
          return unless @hot_load_tracepoint
          @scheduled_at = Datadog::Core::Utils::Time.get_time + EXTRACT_DEBOUNCE_INTERVAL
          @scheduler_signaled = true
          @scheduler_cv.signal
        end
      end

      def log_scope_tree(scope, depth)
        indent = "  " * depth
        @logger.trace { "symdb:   #{indent}#{scope.scope_type} #{scope.name}" }
        scope.scopes&.each { |child| log_scope_tree(child, depth + 1) }
      end

      # Count METHOD scopes with targetable lines inside one FILE scope. Used by
      # extract_and_upload to accumulate the count while streaming, without
      # retaining the Array<Scope> just to compute the total at the end.
      def count_targetable_methods_in_scope(file_scope)
        count = 0
        file_scope.scopes&.each do |class_or_module|
          class_or_module.scopes&.each do |method_scope|
            count += 1 if method_scope.scope_type == "METHOD" && method_scope.targetable_lines?
          end
        end
        count
      end
    end
  end
end
