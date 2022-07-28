# typed: ignore

require_relative 'assets'

module Datadog
  module AppSec
    # Processor integrates libddwaf into datadog/appsec
    class Processor
      # Interface object to check using case .. when
      module IOLike
        def read; end
        def rewind; end

        def self.===(other)
          instance_methods.all? { |meth| other.respond_to?(meth) }
        end
      end

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

        def run(*args)
          start_ns = Core::Utils::Time.get_time(:nanosecond)

          ret, res = @context.run(*args)

          stop_ns = Core::Utils::Time.get_time(:nanosecond)

          @time_ns += res.total_runtime
          @time_ext_ns += (stop_ns - start_ns)
          @timeouts += 1 if res.timeout

          [ret, res]
        end
      end

      attr_reader :ruleset_info, :addresses

      def initialize
        @ruleset = nil
        @handle = nil
        @ruleset_info = nil
        @addresses = nil

        unless load_libddwaf && load_ruleset && create_waf_handle
          Datadog.logger.warn { 'AppSec is disabled, see logged errors above' }
        end
      end

      def ready?
        !@ruleset.nil? && !@handle.nil?
      end

      def new_context
        Context.new(self)
      end

      protected

      attr_reader :handle

      private

      def load_libddwaf
        Processor.require_libddwaf && Processor.libddwaf_provides_waf?
      end

      def load_ruleset
        ruleset_setting = Datadog::AppSec.settings.ruleset

        begin
          @ruleset = case ruleset_setting
                     when :recommended, :risky, :strict
                       JSON.parse(Datadog::AppSec::Assets.waf_rules(ruleset_setting))
                     when String
                       JSON.parse(File.read(ruleset_setting))
                     when IOLike
                       JSON.parse(ruleset_setting.read).tap { ruleset_setting.rewind }
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

      def create_waf_handle
        # TODO: this may need to be reset if the main Datadog logging level changes after initialization
        Datadog::AppSec::WAF.logger = Datadog.logger if Datadog.logger.debug? && Datadog::AppSec.settings.waf_debug

        obfuscator_config = {
          key_regex: Datadog::AppSec.settings.obfuscator_key_regex,
          value_regex: Datadog::AppSec.settings.obfuscator_value_regex,
        }
        @handle = Datadog::AppSec::WAF::Handle.new(@ruleset, obfuscator: obfuscator_config)
        @ruleset_info = @handle.ruleset_info
        @addresses = @handle.required_addresses

        true
      rescue StandardError => e
        Datadog.logger.error do
          "libddwaf failed to initialize, error: #{e.inspect}"
        end

        @ruleset_info = e.ruleset_info if e.respond_to?(:ruleset_info)

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
