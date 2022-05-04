# typed: ignore

require 'datadog/appsec/assets'

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

      def initialize
        @ruleset = nil
        @handle = nil

        unless load_libddwaf && load_ruleset && create_waf_handle
          Datadog.logger.warn { 'AppSec is disabled, see logged errors above' }
        end
      end

      def ready?
        !@ruleset.nil? && !@handle.nil?
      end

      def new_context
        Datadog::AppSec::WAF::Context.new(@handle)
      end

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

        true
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
