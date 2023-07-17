# frozen_string_literal: true

require_relative '../../core/utils/duration'

module Datadog
  module AppSec
    module Configuration
      # Settings
      module Settings
        # rubocop:disable Layout/LineLength
        DEFAULT_OBFUSCATOR_KEY_REGEX = '(?i)(?:p(?:ass)?w(?:or)?d|pass(?:_?phrase)?|secret|(?:api_?|private_?|public_?)key)|token|consumer_?(?:id|key|secret)|sign(?:ed|ature)|bearer|authorization'
        DEFAULT_OBFUSCATOR_VALUE_REGEX = '(?i)(?:p(?:ass)?w(?:or)?d|pass(?:_?phrase)?|secret|(?:api_?|private_?|public_?|access_?|secret_?)key(?:_?id)?|token|consumer_?(?:id|key|secret)|sign(?:ed|ature)?|auth(?:entication|orization)?)(?:\s*=[^;]|"\s*:\s*"[^"]+")|bearer\s+[a-z0-9\._\-]+|token:[a-z0-9]{13}|gh[opsu]_[0-9a-zA-Z]{36}|ey[I-L][\w=-]+\.ey[I-L][\w=-]+(?:\.[\w.+\/=-]+)?|[\-]{5}BEGIN[a-z\s]+PRIVATE\sKEY[\-]{5}[^\-]+[\-]{5}END[a-z\s]+PRIVATE\sKEY|ssh-rsa\s*[a-z0-9\/\.+]{100,}'
        # rubocop:enable Layout/LineLength
        DEFAULT_APPSEC_ENABLED = false
        DEFAULT_APPSEC_RULESET = :recommended
        DEFAULT_APPSEC_WAF_TIMEOUT = 5_000 # us
        DEFAULT_APPSEC_WAF_DEBUG = false
        DEFAULT_APPSEC_TRACE_RATE_LIMIT = 100 # traces/s
        DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_ENABLED = true
        DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE = 'safe'
        APPSEC_VALID_TRACK_USER_EVENTS_MODE = [
          DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE,
          'extended'
        ].freeze

        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/BlockLength
        def self.add_settings!(base)
          base.class_eval do
            settings :appsec do
              option :enabled do |o|
                o.default { env_to_bool('DD_APPSEC_ENABLED', DEFAULT_APPSEC_ENABLED) }
                o.setter do |v|
                  v ? true : false
                end
              end

              define_method(:instrument) do |integration_name|
                if enabled
                  registered_integration = Datadog::AppSec::Contrib::Integration.registry[integration_name]
                  if registered_integration
                    klass = registered_integration.klass
                    if klass.loaded? && klass.compatible?
                      instance = klass.new
                      instance.patcher.patch unless instance.patcher.patched?
                    end
                  end
                end
              end

              option :ruleset do |o|
                o.default { ENV.fetch('DD_APPSEC_RULES', DEFAULT_APPSEC_RULESET) }
              end

              option :ip_denylist do |o|
                o.default { [] }
              end

              option :user_id_denylist do |o|
                o.default { [] }
              end

              option :waf_timeout do |o|
                o.default { ENV.fetch('DD_APPSEC_WAF_TIMEOUT', DEFAULT_APPSEC_WAF_TIMEOUT) } # us
                o.setter do |v|
                  Datadog::Core::Utils::Duration.call(v.to_s, base: :us)
                end
              end

              option :waf_debug do |o|
                o.default { env_to_bool('DD_APPSEC_WAF_DEBUG', DEFAULT_APPSEC_WAF_DEBUG) }
                o.setter do |v|
                  v ? true : false
                end
              end

              option :trace_rate_limit do |o|
                o.default { env_to_int('DD_APPSEC_TRACE_RATE_LIMIT', DEFAULT_APPSEC_TRACE_RATE_LIMIT) } # trace/s
              end

              option :obfuscator_key_regex do |o|
                o.default { ENV.fetch('DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP', DEFAULT_OBFUSCATOR_KEY_REGEX) }
              end

              option :obfuscator_value_regex do |o|
                o.default do
                  ENV.fetch(
                    'DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP',
                    DEFAULT_OBFUSCATOR_VALUE_REGEX
                  )
                end
              end

              settings :track_user_events do
                option :enabled do |o|
                  o.default do
                    ENV.fetch(
                      'DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING',
                      DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_ENABLED
                    )
                  end
                  o.setter do |v|
                    if v
                      v.to_s != 'disabled'
                    else
                      false
                    end
                  end
                end

                option :mode do |o|
                  o.default do
                    ENV.fetch('DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING', DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE)
                  end
                  o.setter do |v|
                    string_value = v.to_s
                    if APPSEC_VALID_TRACK_USER_EVENTS_MODE.include?(string_value)
                      string_value
                    else
                      Datadog.logger.warn(
                        'The appsec.track_user_events.mode value provided is not supported.' \
                        "Supported values are: safe | extended.\n" \
                        'Using default value safe'
                      )
                      DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE
                    end
                  end
                end
              end
            end
          end
        end
        # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/BlockLength
      end
    end
  end
end
