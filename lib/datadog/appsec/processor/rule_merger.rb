# frozen_string_literal: true

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
          def merge(rules:, data: [], overrides: [], exclusions: [])
            combined_rules = combine_rules(rules)

            rules_data = combine_data(data) if data.any?
            rules_overrides = combine_overrides(overrides) if overrides.any?
            rules_exclusions = combine_exclusions(exclusions) if exclusions.any?

            combined_rules['rules_data'] = rules_data if rules_data
            combined_rules['rules_override'] = rules_overrides if rules_overrides
            combined_rules['exclusions'] = rules_exclusions if rules_exclusions

            combined_rules
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
        end
      end
    end
  end
end
