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
          def merge(rules:, data: nil, overrides: nil)
            combined_rules = combine_rules(rules)

            rules_data = combine_data(data) if data
            rules_overrides_and_exclusions = combine_overrides(overrides) if overrides

            combined_rules.merge!(rules_data) if rules_data
            combined_rules.merge!(rules_overrides_and_exclusions) if rules_overrides_and_exclusions
            combined_rules
          end

          private

          def combine_rules(rules)
            return rules[0] if rules.size == 1

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
              data_entry['rules_data'].each do |value|
                data_exists = result.select { |x| x['id'] == value['id'] }

                if data_exists.any?
                  existing_data = data_exists.first

                  if existing_data['type'] == value['type']
                    # Duplicate entry base on type and id
                    # We need to merge the existing data with the new one
                    # and make sure to remove duplicates
                    merged_data = merge_data_base_on_expiration(existing_data['data'], value['data'])
                    existing_data['data'] = merged_data
                  else
                    result << value
                  end
                else
                  # First entry for that id
                  result << value
                end
              end
            end

            return unless result.any?

            { 'rules_data' => result }
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
                expiration = result[data['value']]
                result[data['value']] = data['expiration'] if data['expiration'].nil? || data['expiration'] > expiration
              else
                result[data['value']] = data['expiration']
              end
            end

            result.each_with_object([]) do |entry, acc|
              # There could be cases that there is no experitaion value.
              # To singal that there is no expiration we use the default value 0.
              acc << { 'value' => entry[0], 'expiration' => entry[1] || 0 }
            end
          end

          def combine_overrides(overrides)
            result = {}
            exclusions = []
            rules_override = []

            overrides.each do |override|
              if override['rules_override']
                override['rules_override'].each do |rule_override|
                  rules_override << rule_override
                end
              elsif override['exclusions']
                override['exclusions'].each do |exclusion|
                  exclusions << exclusion
                end
              end
            end

            result['exclusions'] = exclusions if exclusions.any?
            result['rules_override'] = rules_override if rules_override.any?

            return if result.empty?

            result
          end
        end
      end
    end
  end
end
