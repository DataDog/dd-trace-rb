# frozen_string_literal: true

require_relative "../core/utils/only_once"
require_relative "configuration/flag_selection"

module Datadog
  module OpenFeature
    # Logs and counts flag selections that were not sent or that the server ignored.
    # Messages carry reasons and limits only, never the selected values.
    class FlagSelectionReporter
      TELEMETRY_NAMESPACE = "tracers"
      DROPPED_METRIC = "flag_selection.dropped"
      IGNORED_METRIC = "flag_selection.ignored"

      LIMITS = {
        Configuration::FlagSelection::MALFORMED_SELECTION =>
          "flag_selection must be a Hash with optional tags and key_patterns string arrays",
        Configuration::FlagSelection::TOO_MANY_VALUES =>
          "each list accepts at most #{Configuration::FlagSelection::MAX_VALUES} values",
        Configuration::FlagSelection::INVALID_KEY_PATTERN =>
          "each key pattern is at most #{Configuration::FlagSelection::MAX_VALUE_BYTES} UTF-8 bytes",
        Configuration::FlagSelection::INVALID_TAG =>
          "each tag is at most #{Configuration::FlagSelection::MAX_VALUE_BYTES} UTF-8 bytes",
      }.freeze
      URL_LIMIT = "the request URL is at most #{Configuration::FlagSelection::MAX_URL_BYTES} bytes"

      IGNORED_REASONS = [
        Configuration::FlagSelection::MALFORMED_SELECTION,
        Configuration::FlagSelection::TOO_MANY_VALUES,
        Configuration::FlagSelection::INVALID_KEY_PATTERN,
        Configuration::FlagSelection::INVALID_TAG,
        "tag_load_failed",
      ].freeze
      UNKNOWN_REASON = "unknown"
      # Longer than every known reason, so a longer header is never compared.
      MAX_IGNORED_REASON_BYTES = 32

      SELECTION_DIFFERS_WARNING =
        "flag_selection differs from the flag selection already in use in this process. Using the first selection."
      REMOTE_CONFIG_WARNING =
        "flag_selection is not supported when flags are delivered through Remote Config. " \
        "Loading the full flag configuration."

      ONCE_KEYS = [
        *LIMITS.keys.map { |reason| "#{DROPPED_METRIC}:#{reason}" },
        *(IGNORED_REASONS + [UNKNOWN_REASON]).map { |reason| "#{IGNORED_METRIC}:#{reason}" },
        SELECTION_DIFFERS_WARNING,
        REMOTE_CONFIG_WARNING,
      ].freeze

      class << self
        # Called in a forked child too, so it reports for its own process.
        def reset_once_guards
          @once_guards = ONCE_KEYS.map { |key| [key, Core::Utils::OnlyOnce.new] }.to_h.freeze
        end

        def run_once(key, &block)
          @once_guards.fetch(key).run(&block)
        end
      end

      reset_once_guards

      def initialize(logger:, telemetry:)
        @logger = logger
        @telemetry = telemetry
      end

      def report_dropped(reason, limit = LIMITS.fetch(reason))
        @logger.error("flag_selection was not sent (#{reason}: #{limit}). Loading the full flag configuration.")
        count_dropped(reason)
      end

      def count_dropped(reason)
        self.class.run_once("#{DROPPED_METRIC}:#{reason}") { count(DROPPED_METRIC, reason) }
      end

      def report_url_too_long
        report_dropped(Configuration::FlagSelection::TOO_MANY_VALUES, URL_LIMIT)
      end

      def report_ignored(header_value)
        reason = ignored_reason(header_value)
        return unless reason

        self.class.run_once("#{IGNORED_METRIC}:#{reason}") do
          @logger.error("flag_selection was ignored by the server (#{reason}). Loaded the full flag configuration.")
          count(IGNORED_METRIC, reason)
        end
      end

      def warn_selection_differs
        self.class.run_once(SELECTION_DIFFERS_WARNING) { @logger.warn(SELECTION_DIFFERS_WARNING) }
      end

      def warn_remote_config
        self.class.run_once(REMOTE_CONFIG_WARNING) { @logger.warn(REMOTE_CONFIG_WARNING) }
      end

      private

      def ignored_reason(header_value)
        return if header_value.nil? || header_value.empty?
        return UNKNOWN_REASON if header_value.bytesize > MAX_IGNORED_REASON_BYTES

        IGNORED_REASONS.find { |reason| reason == header_value } || UNKNOWN_REASON
      end

      def count(metric_name, reason)
        @telemetry.inc(TELEMETRY_NAMESPACE, metric_name, 1, tags: {reason: reason})
      # Telemetry is best effort and must never interrupt configuration delivery.
      rescue => e
        @logger.debug { "Feature Flags: flag selection telemetry error: #{e.class}: #{e.message}" }
      end
    end
  end
end
