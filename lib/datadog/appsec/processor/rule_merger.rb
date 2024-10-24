# frozen_string_literal: true

require_relative '../assets'

module Datadog
  module AppSec
    class Processor
      # RuleMerger merge different sources of information
      # into the rules payload
      module RuleMerger
        # RuleVersionMismatchError
        class RuleVersionMismatchError < StandardError
          def initialize(version1, version2)
            msg = 'Merging rule files with different version could lead to unkown behaviour. '\
              "We have receieve two rule files with versions: #{version1}, #{version2}. "\
              'Please validate the configuration is correct and try again.'
            super(msg)
          end
        end

        class << self
          # TODO: `processors` and `scanners` are not provided by the caller, consider removing them
          def merge(
            telemetry:,
            rules:, data: [], overrides: [], exclusions: [], custom_rules: [],
            processors: nil, scanners: nil
          )
            processors ||= begin
              default_waf_processors
            rescue StandardError => e
              Datadog.logger.error("libddwaf rulemerger failed to parse default waf processors. Error: #{e.inspect}")
              telemetry.report(
                e,
                description: 'libddwaf rulemerger failed to parse default waf processors'
              )
              []
            end

            scanners ||= begin
              default_waf_scanners
            rescue StandardError => e
              Datadog.logger.error("libddwaf rulemerger failed to parse default waf scanners. Error: #{e.inspect}")
              telemetry.report(
                e,
                description: 'libddwaf rulemerger failed to parse default waf scanners'
              )
              []
            end

            combined_rules = combine_rules(rules)

            combined_data = combine_data(data) if data.any?
            combined_overrides = combine_overrides(overrides) if overrides.any?
            combined_exclusions = combine_exclusions(exclusions) if exclusions.any?
            combined_custom_rules = combine_custom_rules(custom_rules) if custom_rules.any?

            combined_rules['rules_data'] = combined_data if combined_data
            combined_rules['rules_override'] = combined_overrides if combined_overrides
            combined_rules['exclusions'] = combined_exclusions if combined_exclusions
            combined_rules['custom_rules'] = combined_custom_rules if combined_custom_rules
            combined_rules['processors'] = processors
            combined_rules['scanners'] = scanners
            combined_rules
          end

          def default_waf_processors
            @default_waf_processors ||= JSON.parse(Datadog::AppSec::Assets.waf_processors)
          end

          def default_waf_scanners
            @default_waf_scanners ||= JSON.parse(Datadog::AppSec::Assets.waf_scanners)
          end

          private

          def combine_rules(rules)
            return rules[0].dup if rules.size == 1

            final_rules = []
            # @type var final_version: ::String
            final_version = (_ = nil)

            rules.each do |rule_file|
              version = rule_file['version']

              if version && !final_version
                final_version = version
              elsif final_version != version
                raise RuleVersionMismatchError.new(final_version, version)
              end

              final_rules.concat(rule_file['rules'])
            end

            {
              'version' => final_version,
              'rules' => final_rules
            }
          end

          def combine_data(data)
            result = []

            data.each do |data_entry|
              data_entry.each do |value|
                existing_data = result.find { |x| x['id'] == value['id'] }

                if existing_data && existing_data['type'] == value['type']
                  # Duplicate entry base on type and id
                  # We need to merge the existing data with the new one
                  # and make sure to remove duplicates
                  merged_data = merge_data_base_on_expiration(existing_data['data'], value['data'])
                  existing_data['data'] = merged_data
                else
                  result << value
                end
              end
            end

            return unless result.any?

            result
          end

          def merge_data_base_on_expiration(data1, data2)
            result = data1.each_with_object({}) do |value, acc|
              acc[value['value']] = value['expiration']
            end

            data2.each do |data|
              if result.key?(data['value'])
                # The value is duplicated so we need to keep
                # the one with the highest expiration value
                # We replace it if the expiration is higher than the current one
                # or if no experiration
                current_expiration = result[data['value']]
                new_expiration = data['expiration']

                if new_expiration.nil? || current_expiration && new_expiration > current_expiration
                  result[data['value']] = new_expiration
                end
              else
                result[data['value']] = data['expiration']
              end
            end

            result.each_with_object([]) do |entry, acc|
              value = { 'value' => entry[0] }
              value['expiration'] = entry[1] if entry[1]

              acc << value
            end
          end

          def combine_overrides(overrides)
            overrides.flatten
          end

          def combine_exclusions(exclusions)
            exclusions.flatten
          end

          def combine_custom_rules(custom_rules)
            custom_rules.flatten
          end
        end
      end
    end
  end
end
