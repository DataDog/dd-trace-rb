# frozen_string_literal: true

require "set"

require_relative "ext"

module Datadog
  module OpenFeature
    # Copies the selected split's features into flag metadata, one entry per destination,
    # and reads them back by destination prefix.
    module SplitFeatures
      DESTINATION_PREFIXES = {
        "HOOK" => Ext::METADATA_FEATURE_PREFIX,
        "EXPOSURE" => Ext::METADATA_EXPOSURE_FEATURE_PREFIX,
        "EVALUATION" => Ext::METADATA_EVALUATION_FEATURE_PREFIX,
      }.freeze

      # Bounds the memory spent remembering which unknown destinations were already warned about.
      MAX_WARNED_DESTINATIONS = 64

      EMPTY = {}.freeze

      @warned_destinations = Set.new
      @warned_destinations_mutex = Mutex.new

      class << self
        # libdatadog already skips invalid features and keeps the first feature of a repeated key.
        def write(metadata, features)
          features.each do |key, value, destinations|
            destinations.each do |destination|
              prefix = DESTINATION_PREFIXES[destination]
              if prefix
                metadata["#{prefix}#{key}"] = value
              else
                warn_unknown_destination(destination)
              end
            end
          end

          metadata
        end

        def read(metadata, prefix)
          return EMPTY unless metadata.is_a?(Hash)

          features = nil #: features_t?
          metadata.each do |key, value|
            next unless key.is_a?(String) && key.start_with?(prefix)

            (features ||= {})[key[prefix.length, key.length]] = value
          end

          features ? features.freeze : EMPTY
        end

        private

        def reset_warned_destinations_for_tests
          @warned_destinations_mutex.synchronize { @warned_destinations.clear }
        end

        def warn_unknown_destination(destination)
          first = @warned_destinations_mutex.synchronize do
            @warned_destinations.size < MAX_WARNED_DESTINATIONS && !@warned_destinations.add?(destination).nil?
          end
          return unless first

          Datadog.logger.warn(
            "Feature Flags: ignoring unknown split feature destination #{destination.inspect}; " \
            "known destinations are #{DESTINATION_PREFIXES.keys.join(", ")}",
          )
        end
      end
    end
  end
end
