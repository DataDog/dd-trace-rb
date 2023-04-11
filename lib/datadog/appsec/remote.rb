# frozen_string_literal: true

require_relative '../core/remote/dispatcher'
require_relative 'processor/rule_merger'
require_relative 'processor/rule_loader'

module Datadog
  module AppSec
    # Remote
    module Remote
      class ReadError < StandardError; end
      class NoRulesError < StandardError; end

      class << self
        CAP_ASM_ACTIVATION                = 1 << 1 # Remote activation via ASM_FEATURES product
        CAP_ASM_IP_BLOCKING               = 1 << 2 # accept IP blocking data from ASM_DATA product
        CAP_ASM_DD_RULES                  = 1 << 3 # read ASM rules from ASM_DD product
        CAP_ASM_EXCLUSIONS                = 1 << 4 # exclusion filters (passlist) via ASM product
        CAP_ASM_REQUEST_BLOCKING          = 1 << 5 # can block on request info
        CAP_ASM_RESPONSE_BLOCKING         = 1 << 6 # can block on response info
        CAP_ASM_USER_BLOCKING             = 1 << 7 # accept user blocking data from ASM_DATA product
        CAP_ASM_CUSTOM_RULES              = 1 << 8 # accept custom rules
        CAP_ASM_CUSTOM_BLOCKING_RESPONSE  = 1 << 9 # supports custom http code or redirect sa blocking response

        # TODO: we need to dynamically add CAP_ASM_ACTIVATION once we support it
        ASM_CAPABILITIES = [
          CAP_ASM_IP_BLOCKING,
          CAP_ASM_USER_BLOCKING,
          CAP_ASM_CUSTOM_RULES,
          CAP_ASM_EXCLUSIONS,
          CAP_ASM_REQUEST_BLOCKING,
          CAP_ASM_RESPONSE_BLOCKING,
          CAP_ASM_DD_RULES,
        ].freeze

        ASM_PRODUCTS = [
          'ASM_DD',       # Datadog employee issued configuration
          'ASM',          # customer issued configuration (rulesets, passlist...)
          'ASM_FEATURES', # capabilities
          'ASM_DATA',     # config files (IP addresses or users for blocking)
        ].freeze

        def capabilities
          remote_features_enabled? ? ASM_CAPABILITIES : []
        end

        def products
          remote_features_enabled? ? ASM_PRODUCTS : []
        end

        # rubocop:disable Metrics/MethodLength
        def receivers
          return [] unless remote_features_enabled?

          matcher = Core::Remote::Dispatcher::Matcher::Product.new(ASM_PRODUCTS)
          receiver = Core::Remote::Dispatcher::Receiver.new(matcher) do |repository, changes|
            changes.each do |change|
              Datadog.logger.debug { "remote config change: '#{change.path}'" }
            end

            rules = []
            data = []
            overrides = []
            exclusions = []

            asm_data_config_types = ['blocked_ips', 'blocked_users']
            asm_overrides_config_types = ['blocking', 'disabled_rules']

            repository.contents.each do |content|
              case content.path.product
              when 'ASM_DD'
                rules << parse_content(content)
              when 'ASM_DATA'
                data << parse_content(content) if asm_data_config_types.include?(content.path.config_id)
              when 'ASM'
                overrides << parse_content(content) if asm_overrides_config_types.include?(content.path.config_id)
                exclusions << parse_content(content) if content.path.config_id == 'exclusion_filters'
              end
            end

            if rules.empty?
              settings_rules = AppSec::Processor::RuleLoader.load_rules(ruleset: Datadog.configuration.appsec.ruleset)

              raise NoRulesError, 'no default rules available' unless settings_rules

              rules = [settings_rules]
            end

            ruleset = AppSec::Processor::RuleMerger.merge(
              rules: rules,
              data: data,
              overrides: overrides,
              exclusions: exclusions,
            )

            Datadog::AppSec.reconfigure(ruleset: ruleset)
          end

          [receiver]
        end
        # rubocop:enable Metrics/MethodLength

        private

        def remote_features_enabled?
          Datadog::AppSec.send(:default_setting?, :ruleset)
        end

        def parse_content(content)
          data = content.data.read

          content.data.rewind

          raise ReadError, 'EOF reached' if data.nil?

          JSON.parse(data)
        end
      end
    end
  end
end
