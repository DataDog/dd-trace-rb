module Datadog
  module Security
    module Configuration
      # Configuration settings, acting as an integration registry
      # TODO: as with Configuration, this is a trivial implementation
      class Settings
        class << self
          def boolean
            -> (v) { ['1', 'true'].include?((v || '').downcase) }
          end

          def string
            -> (v) { v.to_s }
          end

          def integer
            -> (v) { v.to_i }
          end
        end

        DEFAULTS = {
          enabled: false,
          ruleset: :recommended,
          waf_timeout: 5_000, # us
          waf_debug: false,
          trace_rate_limit: 100, # traces/s
        }

        ENVS = {
          'DD_APPSEC_ENABLED' => [:enabled, Settings.boolean],
          'DD_APPSEC_RULESET' => [:ruleset, Settings.string],
          'DD_APPSEC_WAF_TIMEOUT' => [:waf_timeout, Settings.integer],
          'DD_APPSEC_WAF_DEBUG' => [:waf_debug, Settings.boolean],
          'DD_APPSEC_TRACE_RATE_LIMIT' => [:trace_rate_limit, Settings.integer],
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

        def trace_rate_limit
          @options[:trace_rate_limit]
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
