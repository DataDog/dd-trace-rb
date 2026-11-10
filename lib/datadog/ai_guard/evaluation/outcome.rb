# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Internal outcome of an evaluation request
      #
      # @api private
      class Outcome
        attr_reader :result, :redaction, :extra_tags, :extra_metastruct

        def initialize(result:, redaction:, blocking_enabled:, extra_tags:, extra_metastruct:)
          @result = result
          @redaction = redaction
          @blocking_enabled = blocking_enabled
          @extra_tags = normalize_extra_tags(extra_tags)
          @extra_metastruct = normalize_extra_metastruct(extra_metastruct)
        end

        def block?
          @blocking_enabled && (result.deny? || result.abort?)
        end

        private

        def normalize_extra_tags(entries)
          # @type var tags: Hash[String, String]
          tags = {}

          filter_extra_entries(entries).each do |entry|
            key = entry["key"]
            next if key.start_with?("_dd") || Ext::RESERVED_EXTRA_TAGS.include?(key)

            value = entry["value"]
            tags[key] = value if value.is_a?(String)
          end

          tags
        end

        def normalize_extra_metastruct(entries)
          # @type var metastruct: Hash[String, Helpers::json]
          metastruct = {}

          filter_extra_entries(entries).each do |entry|
            key = entry["key"]
            next if Ext::RESERVED_EXTRA_METASTRUCT_KEYS.include?(key)

            metastruct[key] = entry["value"]
          end

          metastruct
        end

        def filter_extra_entries(entries)
          return [] unless entries.is_a?(Array)

          entries.select do |entry|
            next false unless entry.is_a?(Hash)

            key = entry["key"]
            key.is_a?(String) && !key.empty? && !entry["value"].nil?
          end #: Array[{"key" => String, "value" => Helpers::json}]
        end
      end
    end
  end
end
