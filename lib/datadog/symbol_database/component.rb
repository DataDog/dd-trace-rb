# frozen_string_literal: true

require_relative 'extractor'
require_relative 'scope_context'
require_relative 'uploader'
require_relative '../core/utils/time'

module Datadog
  module SymbolDatabase
    # Main coordinator for symbol database upload functionality.
    #
    # Responsibilities:
    # - Lifecycle management: Initialization, shutdown, upload triggering
    # - Coordination: Connects Extractor → ScopeContext → Uploader
    # - Remote config handling: start_upload called by Remote module on config changes
    # - Deduplication: 60-second cooldown prevents rapid re-uploads
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

      # Build a new Component if feature is enabled and dependencies met.
      # @param settings [Configuration::Settings] Tracer settings
      # @param agent_settings [Configuration::AgentSettings] Agent configuration
      # @param logger [Logger] Logger instance
      # @param telemetry [Telemetry, nil] Optional telemetry for metrics
      # @return [Component, nil] Component instance or nil if not enabled/requirements not met
      def self.build(settings, agent_settings, logger, telemetry: nil)
        return unless settings.respond_to?(:symbol_database) && settings.symbol_database.enabled

        # Requires remote config (unless force mode)
        unless settings.remote&.enabled || settings.symbol_database.force_upload
          logger.debug("SymDB: Symbol Database requires Remote Configuration (or force upload mode)")
          return nil
        end

        new(settings, agent_settings, logger, telemetry: telemetry).tap do |component|
          # Start immediately if force upload mode
          component.start_upload if settings.symbol_database.force_upload
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

        # Build uploader and scope context
        @uploader = Uploader.new(settings, agent_settings, telemetry: telemetry)
        @scope_context = ScopeContext.new(@uploader, telemetry: telemetry)

        @enabled = false
        @last_upload_time = nil
      end

      # Start symbol upload (triggered by remote config or force mode).
      # Extracts symbols from all loaded modules and triggers upload.
      # @return [void]
      def start_upload
        return if @enabled
        return if recently_uploaded?

        @enabled = true
        @last_upload_time = Datadog::Core::Utils::Time.now

        # Trigger extraction and upload
        extract_and_upload
      rescue => e
        Datadog.logger.debug("SymDB: Error starting upload: #{e.class}: #{e}")
      end

      # Stop symbol upload (disable future uploads).
      # @return [void]
      def stop_upload
        @enabled = false
      end

      # Shutdown component and cleanup resources.
      # @return [void]
      def shutdown!
        @scope_context.shutdown
      end

      # @api private
      private

      # Check if upload was recent (within cooldown period).
      # @return [Boolean] true if uploaded within last 60 seconds
      def recently_uploaded?
        return false if @last_upload_time.nil?

        # Don't upload if last upload was within cooldown period
        Datadog::Core::Utils::Time.now - @last_upload_time < UPLOAD_COOLDOWN_INTERVAL
      end

      # Extract symbols from all loaded modules and upload.
      # @return [void]
      def extract_and_upload
        start_time = Datadog::Core::Utils::Time.get_time

        # Iterate all loaded modules and extract symbols
        # Extractor.extract filters to user code only (excludes Datadog::*, gems, stdlib)
        extracted_count = 0
        ObjectSpace.each_object(Module) do |mod|
          scope = Extractor.extract(mod)
          next unless scope

          @scope_context.add_scope(scope)
          extracted_count += 1
        end

        # Flush any remaining scopes
        @scope_context.flush

        # Track extraction metrics
        duration = Datadog::Core::Utils::Time.get_time - start_time
        @telemetry&.distribution('symbol_database.extraction_time', duration)
        @telemetry&.count('symbol_database.scopes_extracted', extracted_count)
      rescue => e
        Datadog.logger.debug("SymDB: Error during extraction: #{e.class}: #{e}")
        @telemetry&.count('symbol_database.extraction_error', 1)
      end
    end
  end
end
