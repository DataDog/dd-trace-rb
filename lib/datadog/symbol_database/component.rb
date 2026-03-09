# frozen_string_literal: true

require_relative 'extractor'
require_relative 'scope_context'
require_relative 'uploader'
require_relative '../core/utils/time'

module Datadog
  module SymbolDatabase
    # Coordinates symbol database components and manages lifecycle
    class Component
      UPLOAD_COOLDOWN = 60  # seconds

      def self.build(settings, agent_settings, logger, telemetry: nil)
        return unless settings.respond_to?(:symbol_database) && settings.symbol_database.enabled

        # Symbol database requires DI to be enabled
        unless settings.respond_to?(:dynamic_instrumentation) && settings.dynamic_instrumentation.enabled
          logger.debug("SymDB: Symbol Database requires Dynamic Instrumentation to be enabled")
          return nil
        end

        # Requires remote config (unless force mode)
        unless settings.remote&.enabled || settings.symbol_database.force_upload
          logger.debug("SymDB: Symbol Database requires Remote Configuration (or force upload mode)")
          return nil
        end

        new(settings, agent_settings, logger, telemetry: telemetry).tap do |component|
          SymbolDatabase.set_component(component)

          # Start immediately if force upload mode
          component.start_upload if settings.symbol_database.force_upload
        end
      end

      attr_reader :settings

      def initialize(settings, agent_settings, logger, telemetry: nil)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
        @telemetry = telemetry

        # Build uploader and scope context
        @uploader = Uploader.new(settings)
        @scope_context = ScopeContext.new(@uploader)

        @enabled = false
        @last_upload_time = nil
      end

      # Start symbol upload (triggered by remote config or force mode)
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

      # Stop symbol upload
      def stop_upload
        @enabled = false
      end

      # Shutdown component
      def shutdown!
        SymbolDatabase.set_component(nil)
        @scope_context.shutdown
      end

      private

      def recently_uploaded?
        return false if @last_upload_time.nil?

        # Don't upload if last upload was within cooldown period
        Datadog::Core::Utils::Time.now - @last_upload_time < UPLOAD_COOLDOWN
      end

      def extract_and_upload
        # Iterate all loaded modules and extract symbols
        ObjectSpace.each_object(Module) do |mod|
          scope = Extractor.extract(mod)
          next unless scope

          @scope_context.add_scope(scope)
        end

        # Flush any remaining scopes
        @scope_context.flush
      rescue => e
        Datadog.logger.debug("SymDB: Error during extraction: #{e.class}: #{e}")
      end
    end
  end
end
