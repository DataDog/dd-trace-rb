# frozen_string_literal: true

require_relative 'extractor'
require_relative 'logger'
require_relative 'scope_context'
require_relative 'uploader'
require_relative '../core/utils/time'
require_relative '../core/utils/only_once'

module Datadog
  module SymbolDatabase
    # Main coordinator for symbol database upload functionality.
    #
    # Responsibilities:
    # - Lifecycle management: Initialization, shutdown, upload triggering
    # - Coordination: Connects Extractor → ScopeContext → Uploader
    # - Remote config handling: start_upload called by Remote module on config changes
    # - Deduplication: cooldown prevents rapid re-uploads (see UPLOAD_COOLDOWN_INTERVAL)
    #
    # Upload flow:
    # 1. Remote config sends upload_symbols: true (or force_upload mode)
    # 2. start_upload called
    # 3. extract_and_upload: ObjectSpace iteration → Extractor → ScopeContext
    # 4. ScopeContext batches and triggers Uploader
    #
    # Created by: Components#initialize (in Core::Configuration::Components)
    # Accessed by: Remote config receiver via Datadog.send(:components).symbol_database
    # Requires: Remote config enabled (unless force mode)
    #
    # @api private
    class Component
      UPLOAD_COOLDOWN_INTERVAL = 60  # seconds

      # Class-level guard: force_upload extraction should only happen once per process,
      # even if Components is rebuilt multiple times during startup (reconfigurations).
      FORCE_UPLOAD_ONCE = Core::Utils::OnlyOnce.new

      # Build a new Component if feature is enabled and dependencies met.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      # @param telemetry [Telemetry, nil] Optional telemetry for metrics
      # @return [Component, nil] Component instance or nil if not enabled/requirements not met
      def self.build(settings, agent_settings, logger, telemetry: nil)
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

        new(settings, agent_settings, symdb_logger, telemetry: telemetry).tap do |component|
          # Defer extraction if force upload mode — wait for app boot to complete
          component.schedule_deferred_upload if settings.symbol_database.internal.force_upload
        end
      end

      attr_reader :settings

      # Initialize component.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      # @param telemetry [Telemetry, nil] Optional telemetry for metrics
      def initialize(settings, agent_settings, logger, telemetry: nil)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
        @telemetry = telemetry

        # Build components
        @extractor = Extractor.new(logger: logger, settings: settings, telemetry: telemetry)
        @uploader = Uploader.new(settings, agent_settings, logger: logger, telemetry: telemetry)
        @scope_context = ScopeContext.new(@uploader, logger: logger, telemetry: telemetry)

        @enabled = false
        @last_upload_time = nil
        @mutex = Mutex.new
        @upload_in_progress = false
        @shutdown = false
      end

      # Schedule a deferred upload that waits for app boot to complete.
      #
      # In Rails: uses ActiveSupport.on_load(:after_initialize) to wait for
      # Zeitwerk eager loading to finish before extracting symbols.
      #
      # In non-Rails: runs extraction immediately since there is no deferred
      # class loading to wait for.
      #
      # Uses FORCE_UPLOAD_ONCE to ensure only one extraction happens per process,
      # even when Components is rebuilt multiple times during startup.
      #
      # @return [void]
      def schedule_deferred_upload
        if defined?(::ActiveSupport) && defined?(::Rails::Railtie)
          # Rails detected: defer until after_initialize when Zeitwerk has
          # eager-loaded all application classes.
          #
          # Look up the current component at callback-fire time (not build time),
          # because reconfigurations during startup may shut down and replace the
          # component that originally registered this callback.
          FORCE_UPLOAD_ONCE.run do
            ::ActiveSupport.on_load(:after_initialize) do
              current = begin
                Datadog.send(:components).symbol_database
              rescue
                nil
              end
              current&.start_upload
            end
          end
        else
          # Non-Rails: no deferred loading, extract immediately.
          # Still guarded by OnlyOnce to handle reconfigurations.
          FORCE_UPLOAD_ONCE.run do
            start_upload
          end
        end
      end

      # Whether this component has been shut down.
      # @return [Boolean]
      def shutdown?
        @mutex.synchronize { @shutdown }
      end

      # Start symbol upload (triggered by remote config or force mode).
      # Extracts symbols from all loaded modules and triggers upload.
      # Thread-safe: can be called concurrently from multiple remote config updates.
      # @return [void]
      def start_upload
        should_upload = false

        @mutex.synchronize do
          return if @shutdown
          return if @enabled
          if recently_uploaded?
            @logger.trace { "symdb: cooldown active, skipping upload" }
            return
          end

          @enabled = true
          @last_upload_time = Datadog::Core::Utils::Time.now
          should_upload = true
        end

        # Trigger extraction and upload outside mutex (long-running operation)
        extract_and_upload if should_upload
      rescue => e
        @logger.debug { "symdb: error starting upload: #{e.class}: #{e}" }
        @telemetry&.inc('tracers', 'symbol_database.start_upload_error', 1)
      end

      # Stop symbol upload (disable future uploads).
      # Thread-safe: can be called concurrently from multiple remote config updates.
      # @return [void]
      def stop_upload
        @mutex.synchronize { @enabled = false }
      end

      # Shutdown component and cleanup resources.
      # Marks component as shut down so deferred uploads are cancelled.
      # Waits for any in-flight upload to complete before shutting down.
      # @return [void]
      def shutdown!
        @mutex.synchronize { @shutdown = true }

        # Wait for in-flight upload to complete (max 5 seconds)
        deadline = Datadog::Core::Utils::Time.now + 5
        while @upload_in_progress && Datadog::Core::Utils::Time.now < deadline
          sleep 0.1
        end

        @scope_context.shutdown
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

      # Check if upload was recent (within cooldown period).
      # Must be called from within @mutex.synchronize.
      # @return [Boolean] true if uploaded within last UPLOAD_COOLDOWN_INTERVAL seconds
      def recently_uploaded?
        return false if @last_upload_time.nil?

        # Don't upload if last upload was within cooldown period
        # steep:ignore:start
        (Datadog::Core::Utils::Time.now - @last_upload_time) < UPLOAD_COOLDOWN_INTERVAL
        # steep:ignore:end
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
            @scope_context.add_scope(scope)
            extracted_count += 1
          end

          # Flush any remaining scopes
          @scope_context.flush

          # Track extraction metrics
          duration = Datadog::Core::Utils::Time.get_time - start_time
          @telemetry&.distribution('tracers', 'symbol_database.extraction_time', duration)
          @telemetry&.inc('tracers', 'symbol_database.scopes_extracted', extracted_count)
        rescue => e
          @logger.debug { "symdb: extraction error: #{e.class}: #{e}" }
          @telemetry&.inc('tracers', 'symbol_database.extraction_error', 1)
        ensure
          @mutex.synchronize { @upload_in_progress = false }
        end
      end
    end
  end
end
