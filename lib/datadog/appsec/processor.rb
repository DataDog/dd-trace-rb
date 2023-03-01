require_relative 'assets'

module Datadog
  module AppSec
    # Processor integrates libddwaf into datadog/appsec
    class Processor
      # Context manages a sequence of runs
      class Context
        attr_reader :time_ns, :time_ext_ns, :timeouts, :events

        def initialize(processor)
          @context = Datadog::AppSec::WAF::Context.new(processor.send(:handle))
          @time_ns = 0.0
          @time_ext_ns = 0.0
          @timeouts = 0
          @events = []
        end

        def run(input, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
          start_ns = Core::Utils::Time.get_time(:nanosecond)

          # TODO: remove multiple assignment
          _code, res = _ = @context.run(input, timeout)
          # @type var res: WAF::Result

          stop_ns = Core::Utils::Time.get_time(:nanosecond)

          @time_ns += res.total_runtime
          @time_ext_ns += (stop_ns - start_ns)
          @timeouts += 1 if res.timeout

          res
        end

        def finalize
          @context.finalize
        end
      end

      class << self
        def active_context
          Thread.current[:datadog_current_waf_context]
        end

        private

        def active_context=(context)
          unless context.instance_of?(Context)
            raise ArgumentError,
              "The context provide: #{context.inspect} is not a Datadog::AppSec::Processor::Context"
          end

          Thread.current[:datadog_current_waf_context] = context
        end

        def reset_active_context
          Thread.current[:datadog_current_waf_context] = nil
        end
      end

      class NoActiveContextError < StandardError; end
      class AlreadyActiveContextError < StandardError; end

      attr_reader :ruleset_info, :addresses

      def initialize
        @ruleset_info = nil
        @addresses = []
        settings = Datadog::AppSec.settings

        unless load_libddwaf && load_ruleset(settings) && create_waf_handle(settings)
          Datadog.logger.warn { 'AppSec is disabled, see logged errors above' }

          return
        end

        apply_denylist_data(settings)
      end

      def ready?
        !@ruleset.nil? && !@handle.nil?
      end

      def new_context
        Context.new(self)
      end

      def activate_context
        existing_active_context = Processor.active_context
        raise AlreadyActiveContextError if existing_active_context

        context = new_context
        Processor.send(:active_context=, context)
        context
      end

      def deactivate_context
        context = Processor.active_context
        raise NoActiveContextError unless context

        Processor.send(:reset_active_context)
        context.finalize
      end

      def update_rule_data(data)
        @handle.update_rule_data(data)
      end

      def toggle_rules(map)
        @handle.toggle_rules(map)
      end

      def finalize
        @handle.finalize
      end

      protected

      attr_reader :handle

      private

      def apply_denylist_data(settings)
        ruledata_setting = []
        ruledata_setting << denylist_data('blocked_ips', settings.ip_denylist)
        ruledata_setting << denylist_data('blocked_users', settings.user_id_denylist)

        update_rule_data(ruledata_setting)
      end

      def denylist_data(id, denylist)
        {
          'id' => id,
          'type' => 'data_with_expiration',
          'data' => denylist.map { |v| { 'value' => v.to_s, 'expiration' => 2**63 } }
        }
      end

      def load_libddwaf
        Processor.require_libddwaf && Processor.libddwaf_provides_waf?
      end

      def load_ruleset(settings)
        ruleset_setting = settings.ruleset

        begin
          @ruleset = case ruleset_setting
                     when :recommended, :strict
                       JSON.parse(Datadog::AppSec::Assets.waf_rules(ruleset_setting))
                     when :risky
                       JSON.parse(Datadog::AppSec::Assets.waf_rules(:recommended))
                       Datadog.logger.warn(
                         'The :risky Application Security Management ruleset has been deprecated and no longer available.'\
                         'The `:recommended` ruleset will be used instead.'\
                         'Please remove the `appsec.ruleset = :risky` setting from your Datadog.configure block.'
                       )
                     when String
                       JSON.parse(File.read(ruleset_setting))
                     when File, StringIO
                       JSON.parse(ruleset_setting.read || '').tap { ruleset_setting.rewind }
                     when Hash
                       ruleset_setting
                     else
                       raise ArgumentError, "unsupported value for ruleset setting: #{ruleset_setting.inspect}"
                     end

          true
        rescue StandardError => e
          Datadog.logger.error do
            "libddwaf ruleset failed to load, ruleset: #{ruleset_setting.inspect} error: #{e.inspect}"
          end

          false
        end
      end

      def create_waf_handle(settings)
        # TODO: this may need to be reset if the main Datadog logging level changes after initialization
        Datadog::AppSec::WAF.logger = Datadog.logger if Datadog.logger.debug? && settings.waf_debug

        obfuscator_config = {
          key_regex: settings.obfuscator_key_regex,
          value_regex: settings.obfuscator_value_regex,
        }
        @handle = Datadog::AppSec::WAF::Handle.new(@ruleset, obfuscator: obfuscator_config)
        @ruleset_info = @handle.ruleset_info
        @addresses = @handle.required_addresses

        true
      rescue WAF::LibDDWAF::Error => e
        Datadog.logger.error do
          "libddwaf failed to initialize, error: #{e.inspect}"
        end

        @ruleset_info = e.ruleset_info if e.ruleset_info

        false
      rescue StandardError => e
        Datadog.logger.error do
          "libddwaf failed to initialize, error: #{e.inspect}"
        end

        false
      end

      class << self
        # check whether libddwaf is required *and* able to provide the needed feature
        def libddwaf_provides_waf?
          defined?(Datadog::AppSec::WAF) ? true : false
        end

        # libddwaf raises a LoadError on unsupported platforms; it may at some
        # point succeed in being required yet not provide a specific needed feature.
        def require_libddwaf
          Datadog.logger.debug { "libddwaf platform: #{libddwaf_platform}" }

          require 'libddwaf'

          true
        rescue LoadError => e
          Datadog.logger.error do
            'libddwaf failed to load,' \
              "installed platform: #{libddwaf_platform} ruby platforms: #{ruby_platforms} error: #{e.inspect}"
          end

          false
        end

        def libddwaf_spec
          Gem.loaded_specs['libddwaf']
        end

        def libddwaf_platform
          libddwaf_spec ? libddwaf_spec.platform.to_s : 'unknown'
        end

        def ruby_platforms
          Gem.platforms.map(&:to_s)
        end
      end
    end
  end
end
