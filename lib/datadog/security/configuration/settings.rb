module Datadog
  module Security
    module Configuration
      # Configuration settings, acting as an integration registry
      # TODO: as with Configuration, this is a trivial implementation
      class Settings
        DEFAULTS = {
          enabled: false,
          ruleset: :recommended,
          waf_timeout: 5_000, # us
          waf_debug: false,
        }

        ENVS = {
          'DD_APPSEC_ENABLED' => [:enabled, -> (v) { ['1', 'true'].include?((v || '').downcase) }],
          'DD_APPSEC_RULESET' => [:ruleset, -> (v) { v.to_s }],
          'DD_APPSEC_WAF_TIMEOUT' => [:waf_timeout, -> (v) { v.to_i }],
          'DD_APPSEC_WAF_DEBUG' => [:waf_debug, -> (v) { ['1', 'true'].include?((v || '').downcase) }],
        }

        Integration = Struct.new(:integration, :options)

        def initialize
          @integrations = []
          @options = DEFAULTS.dup.tap do |options|
            ENVS.each do |env, (key, conv)|
              options[key] = conv.call(ENV[env]) if ENV[env]
            end
          end
        end

        def ruleset
          @options[:ruleset]
        end

        def waf_timeout
          @options[:waf_timeout]
        end

        def waf_debug
          @options[:waf_debug]
        end

        def merge(dsl)
          dsl.options.each do |k, v|
            @options[k] = v unless v.nil?
          end

          return self unless @options[:enabled]

          # patcher.patch may call configure again, hence merge might be called again so it needs to be reentrant
          dsl.instruments.each do |instrument|
            registered_integration = Datadog::Security::Contrib::Integration.registry[instrument.name]
            @integrations << Integration.new(registered_integration, instrument.options)

            # TODO: move to a separate apply step
            klass = registered_integration.klass
            if klass.loaded? && klass.compatible?
              instance = klass.new
              instance.patcher.patch
            end
          end

          self
        end
      end
    end
  end
end
