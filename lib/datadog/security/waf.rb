require 'libsqreen'
require 'datadog/security/assets'

module Datadog
  module Security
    module WAF
      class Args < Hash; end

      class Rules < Hash; end

      module_function

      # TODO: logger
      def logger
        @logger ||= ::Logger.new(STDOUT)
        @logger.level = ::Logger::DEBUG
        #@logger.level = ::Logger::WARN
        @logger.debug { 'waf logger enabled' }
        @logger
      end

      def rules
        @rules ||= JSON.dump(JSON.parse(Assets.waf_rules))
      end

      def name
        rule_name = 'waf_rules'
        @name ||= format('%s_%s', SecureRandom.uuid, rule_name)
      end

      def load_rules
        LibSqreen::WAF.logger = logger
        #LibSqreen::WAF.log_level = :debug
        LibSqreen::WAF[name] = rules
        puts name
      end

      def run(waf_args)
        logger.debug { "waf ruleset: #{name}" }
        action, data = ::LibSqreen::WAF.run(name, waf_args, 5000000, 50000000)

        block = false

        case action
        when :monitor
          logger.debug { "WAF: #{data.inspect}" }
          #record_event({ waf_data: data }, false)
        when :block
          logger.debug { "WAF: #{data.inspect}" }
          #record_event({ waf_data: data }, true)
          block = true
        when :good
          logger.debug { "WAF OK: #{data.inspect}" }
        when :timeout
          logger.debug { "WAF TIMEOUT: #{data.inspect}" }
        when :invalid_call
          logger.debug { "WAF CALL ERROR: #{data.inspect}" }
        when :invalid_rule, :invalid_flow, :no_rule
          logger.debug { "WAF RULE ERROR: #{data.inspect}" }
        else
          logger.debug { "WAF UNKNOWN: #{action.inspect} #{data.inspect}" }
        end

        block
      end
    end
  end
end
