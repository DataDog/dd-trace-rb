# frozen_string_literal: true

require 'libdatadog'

require_relative 'tag_builder'

module Datadog
  module Core
    module Crashtracking
      # Used to report Ruby VM crashes.
      #
      # NOTE: The crashtracker native state is a singleton;
      # so even if you create multiple instances of `Crashtracking::Component` and start them,
      # it only works as "last writer wins". Same for stop -- there's only one state, so calling stop
      # on it will stop the crash tracker, regardless of which instance started it.
      #
      # Methods prefixed with _native_ are implemented in `crashtracker.c`
      class Component
        def self.build(settings, agent_settings, logger:)
          tags = latest_tags(settings)
          agent_base_url = agent_settings.url

          ld_library_path = ::Libdatadog.ld_library_path
          logger.warn('Missing ld_library_path; cannot enable crash tracking') unless ld_library_path

          path_to_crashtracking_receiver_binary = ::Libdatadog.path_to_crashtracking_receiver_binary
          unless path_to_crashtracking_receiver_binary
            logger.warn('Missing path_to_crashtracking_receiver_binary; cannot enable crash tracking')
          end

          return unless agent_base_url
          return unless ld_library_path
          return unless path_to_crashtracking_receiver_binary

          new(
            tags: tags,
            agent_base_url: agent_base_url,
            ld_library_path: ld_library_path,
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            logger: logger
          ).tap(&:start)
        end

        # Reports unhandled exceptions to the crash tracker if available and appropriate.
        # This is called from the at_exit hook to report unhandled exceptions.
        def self.report_unhandled_exception(exception)
          return unless exception && !exception.is_a?(SystemExit) && !exception.is_a?(NoMemoryError)

          begin
            crashtracker = Datadog.send(:components, allow_initialization: false)&.crashtracker
            return unless crashtracker

            crashtracker.report_unhandled_exception(exception)
          rescue => e
            # Unhandled exception report triggering means that the application is already in a bad state
            # We don't want to swallow non-StandardError exceptions here; we would rather just let the
            # application crash
            Datadog.logger.debug("Crashtracker failed to report unhandled exception: #{e.message}")
          end
        end

        # Gets the latest tags from the current configuration.
        #
        # We always fetch fresh tags because:
        # After forking, we need the latest tags, not the parent's tags, such as the pid or runtime-id
        def self.latest_tags(settings)
          TagBuilder.call(settings)
        end

        def initialize(tags:, agent_base_url:, ld_library_path:, path_to_crashtracking_receiver_binary:, logger:)
          @tags = tags
          @agent_base_url = agent_base_url
          @ld_library_path = ld_library_path
          @path_to_crashtracking_receiver_binary = path_to_crashtracking_receiver_binary
          @logger = logger
        end

        def start
          start_or_update_on_fork(action: :start, tags: tags)
        end

        def update_on_fork(settings: Datadog.configuration)
          # Here we pick up the latest settings, so that we pick up any tags that change after forking
          # such as the pid or runtime-id
          start_or_update_on_fork(action: :update_on_fork, tags: self.class.latest_tags(settings))
        end

        def report_unhandled_exception(exception, settings: Datadog.configuration)
          # Maximum number of stack frames to include in exception crash reports
          # This is the same number used for profiling and signal-based crashtracking
          max_exception_stack_frames = 400

          current_tags = self.class.latest_tags(settings)
          # extract all frame data upfront; c expects exactly 3 elements, proper types, no nils
          # limit to max_exception_stack_frames frames
          all_backtrace_locations = exception.backtrace_locations || []
          was_truncated = all_backtrace_locations.length > max_exception_stack_frames

          backtrace_slice = all_backtrace_locations[0...max_exception_stack_frames] || []
          # @type var frames_data: Array[[String, String, Integer]]
          frames_data = backtrace_slice.map do |loc|
            file = loc.path
            file = '<unknown>' if file.nil? || file.empty? || !file.is_a?(String)

            function = loc.label
            function = '<unknown>' if function.nil? || function.empty? || !function.is_a?(String)

            line = loc.lineno
            line = 0 if line.nil? || line < 0 || !line.is_a?(Integer)

            [file, function, line] # Always String, String, Integer
          end

          # Add truncation indicator frame if we had to cut off frames
          if was_truncated
            truncated_count = all_backtrace_locations.length - max_exception_stack_frames
            frames_data << ['<truncated>', "<truncated #{truncated_count} more frames>", 0]
          end

          message = "Unhandled #{exception.class}: #{exception.message || "<no message>"}"

          success = self.class._native_report_ruby_exception(
            agent_base_url,
            message,
            frames_data,
            current_tags.to_a,
            Datadog::VERSION::STRING
          )

          logger.debug('Crashtracker failed to report unhandled exception to crash tracker') unless success
        end

        def stop
          self.class._native_stop
          logger.debug('Crash tracking stopped successfully')
        rescue => e
          logger.error("Failed to stop crash tracking: #{e.message}")
        end

        private

        attr_reader :tags, :agent_base_url, :ld_library_path, :path_to_crashtracking_receiver_binary, :logger

        def start_or_update_on_fork(action:, tags:)
          self.class._native_start_or_update_on_fork(
            action: action,
            agent_base_url: agent_base_url,
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            ld_library_path: ld_library_path,
            tags_as_array: tags.to_a,
            # @ivoanjo: On my machine this needs to be > 5 seconds, and seems to work with 10; the extra 15 is extra margin
            upload_timeout_seconds: 15,
          )
          logger.debug("Crash tracking action: #{action} successful")
        rescue => e
          logger.error("Failed to #{action} crash tracking: #{e.message}")
        end
      end
    end
  end
end
