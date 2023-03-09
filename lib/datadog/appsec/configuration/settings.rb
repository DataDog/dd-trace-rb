module Datadog
  module AppSec
    module Configuration
      # Configuration settings, acting as an integration registry
      # TODO: as with Configuration, this is a trivial implementation
      class Settings
        class << self
          def boolean
            # @type ^(::String) -> bool
            ->(v) do # rubocop:disable Style/Lambda
              case v
              when /(1|true)/i
                true
              when /(0|false)/i, nil
                false
              else
                raise ArgumentError, "invalid boolean: #{v.inspect}"
              end
            end
          end

          # TODO: allow symbols
          def string
            # @type ^(::String) -> ::String
            ->(v) { v.to_s }
          end

          def integer
            # @type ^(::String) -> ::Integer
            ->(v) do # rubocop:disable Style/Lambda
              case v
              when /(\d+)/
                Regexp.last_match(1).to_i
              else
                raise ArgumentError, "invalid integer: #{v.inspect}"
              end
            end
          end

          # rubocop:disable Metrics/MethodLength
          def duration(base = :ns, type = :integer)
            # @type ^(::String) -> ::Integer | ::Float
            ->(v) do # rubocop:disable Style/Lambda
              cast = case type
                     when :integer, Integer
                       method(:Integer)
                     when :float, Float
                       method(:Float)
                     else
                       raise ArgumentError, "invalid type: #{v.inspect}"
                     end

              scale = case base
                      when :s
                        1_000_000_000
                      when :ms
                        1_000_000
                      when :us
                        1000
                      when :ns
                        1
                      else
                        raise ArgumentError, "invalid base: #{v.inspect}"
                      end

              case v
              when /^(\d+)h$/
                cast.call(Regexp.last_match(1)) * 1_000_000_000 * 60 * 60 / scale
              when /^(\d+)m$/
                cast.call(Regexp.last_match(1)) * 1_000_000_000 * 60 / scale
              when /^(\d+)s$/
                cast.call(Regexp.last_match(1)) * 1_000_000_000 / scale
              when /^(\d+)ms$/
                cast.call(Regexp.last_match(1)) * 1_000_000 / scale
              when /^(\d+)us$/
                cast.call(Regexp.last_match(1)) * 1_000 / scale
              when /^(\d+)ns$/
                cast.call(Regexp.last_match(1)) / scale
              when /^(\d+)$/
                cast.call(Regexp.last_match(1))
              else
                raise ArgumentError, "invalid duration: #{v.inspect}"
              end
            end
          end
          # rubocop:enable Metrics/MethodLength
        end

        # rubocop:disable Layout/LineLength
        DEFAULT_OBFUSCATOR_KEY_REGEX = '(?i)(?:p(?:ass)?w(?:or)?d|pass(?:_?phrase)?|secret|(?:api_?|private_?|public_?)key)|token|consumer_?(?:id|key|secret)|sign(?:ed|ature)|bearer|authorization'.freeze
        DEFAULT_OBFUSCATOR_VALUE_REGEX = '(?i)(?:p(?:ass)?w(?:or)?d|pass(?:_?phrase)?|secret|(?:api_?|private_?|public_?|access_?|secret_?)key(?:_?id)?|token|consumer_?(?:id|key|secret)|sign(?:ed|ature)?|auth(?:entication|orization)?)(?:\s*=[^;]|"\s*:\s*"[^"]+")|bearer\s+[a-z0-9\._\-]+|token:[a-z0-9]{13}|gh[opsu]_[0-9a-zA-Z]{36}|ey[I-L][\w=-]+\.ey[I-L][\w=-]+(?:\.[\w.+\/=-]+)?|[\-]{5}BEGIN[a-z\s]+PRIVATE\sKEY[\-]{5}[^\-]+[\-]{5}END[a-z\s]+PRIVATE\sKEY|ssh-rsa\s*[a-z0-9\/\.+]{100,}'.freeze
        # rubocop:enable Layout/LineLength

        DEFAULTS = {
          enabled: false,
          ruleset: :recommended,
          waf_timeout: 5_000, # us
          waf_debug: false,
          trace_rate_limit: 100, # traces/s
          obfuscator_key_regex: DEFAULT_OBFUSCATOR_KEY_REGEX,
          obfuscator_value_regex: DEFAULT_OBFUSCATOR_VALUE_REGEX,
        }.freeze

        ENVS = {
          'DD_APPSEC_ENABLED' => [:enabled, Settings.boolean],
          'DD_APPSEC_RULES' => [:ruleset, Settings.string],
          'DD_APPSEC_WAF_TIMEOUT' => [:waf_timeout, Settings.duration(:us)],
          'DD_APPSEC_WAF_DEBUG' => [:waf_debug, Settings.boolean],
          'DD_APPSEC_TRACE_RATE_LIMIT' => [:trace_rate_limit, Settings.integer],
          'DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP' => [:obfuscator_key_regex, Settings.string],
          'DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP' => [:obfuscator_value_regex, Settings.string],
        }.freeze

        # Struct constant whisker cast for Steep
        Integration = _ = Struct.new(:integration, :options) # rubocop:disable Naming/ConstantName

        def initialize
          @integrations = []
          @options = DEFAULTS.dup.tap do |options|
            ENVS.each do |env, (key, conv)|
              options[key] = conv.call(ENV[env]) if ENV[env]
            end
          end
        end

        def enabled
          # Cast for Steep
          _ = @options[:enabled]
        end

        def ruleset
          # Cast for Steep
          _ = @options[:ruleset]
        end

        # EXPERIMENTAL: This configurable is not meant to be publicly used, but
        #               is very useful for testing. It may change at any point in time.
        def ip_denylist
          # Cast for Steep
          _ = @options[:ip_denylist] || []
        end

        # EXPERIMENTAL: This configurable is not meant to be publicly used, but
        #               is very useful for testing. It may change at any point in time.
        def user_id_denylist
          # Cast for Steep
          _ = @options[:user_id_denylist] || []
        end

        def waf_timeout
          # Cast for Steep
          _ = @options[:waf_timeout]
        end

        def waf_debug
          # Cast for Steep
          _ = @options[:waf_debug]
        end

        def trace_rate_limit
          # Cast for Steep
          _ = @options[:trace_rate_limit]
        end

        def obfuscator_key_regex
          # Cast for Steep
          _ = @options[:obfuscator_key_regex]
        end

        def obfuscator_value_regex
          # Cast for Steep
          _ = @options[:obfuscator_value_regex]
        end

        def [](integration_name)
          integration = Datadog::AppSec::Contrib::Integration.registry[integration_name]

          raise ArgumentError, "'#{integration_name}' is not a valid integration." unless integration

          integration.options
        end

        def merge(dsl)
          dsl.options.each do |k, v|
            @options[k] = v unless v.nil?
          end

          return self unless @options[:enabled]

          # patcher.patch may call configure again, hence merge might be called again so it needs to be reentrant
          dsl.instruments.each do |instrument|
            # TODO: error handling
            registered_integration = Datadog::AppSec::Contrib::Integration.registry[instrument.name]
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

        private

        # Restore to original state, for testing only.
        def reset!
          initialize
        end
      end
    end
  end
end
