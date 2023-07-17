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
        APPSEC_VALID_TRACK_USER_EVENTS_MODE = [
          'safe',
          'extended'
        ].freeze
        APPSEC_VALID_TRACK_USER_EVENTS_ENABLED_VALUES = [
          '1',
          'true'
        ].concat(APPSEC_VALID_TRACK_USER_EVENTS_MODE).freeze

        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/BlockLength
        def self.add_settings!(base)
          base.class_eval do
            settings :appsec do
              option :enabled do |o|
                o.type :bool
                o.env 'DD_APPSEC_ENABLED'
                o.default false
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
                o.env 'DD_APPSEC_RULES'
                o.default :recommended
              end

              option :ip_denylist do |o|
                o.type :array
                o.default []
              end

              option :user_id_denylist do |o|
                o.type :array
                o.default []
              end

              option :waf_timeout do |o|
                o.env 'DD_APPSEC_WAF_TIMEOUT' # us
                o.default 5_000
                o.setter do |v|
                  Datadog::Core::Utils::Duration.call(v.to_s, base: :us)
                end
              end

              option :waf_debug do |o|
                o.env 'DD_APPSEC_WAF_DEBUG'
                o.default false
                o.type :bool
              end

              option :trace_rate_limit do |o|
                o.type :int
                o.env 'DD_APPSEC_TRACE_RATE_LIMIT' # trace/s
                o.default 100
              end

              option :obfuscator_key_regex do |o|
                o.type :string
                o.env 'DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP'
                o.default DEFAULT_OBFUSCATOR_KEY_REGEX
              end

              option :obfuscator_value_regex do |o|
                o.type :string
                o.env 'DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP'
                o.default DEFAULT_OBFUSCATOR_VALUE_REGEX
              end

              settings :block do
                # HTTP status code to block with
                option :status do |o|
                  o.default { 403 }
                end

                # only applies to redirect status codes
                option :location do |o|
                  o.setter { |v| URI(v) unless v.nil? }
                end

                # only applies to non-redirect status codes with bodies
                option :templates do |o|
                  o.default do
                    json = ENV.fetch(
                      'DD_APPSEC_HTTP_BLOCKED_TEMPLATE_JSON',
                      :json
                    )

                    html = ENV.fetch(
                      'DD_APPSEC_HTTP_BLOCKED_TEMPLATE_HTML',
                      :html
                    )

                    text = ENV.fetch(
                      'DD_APPSEC_HTTP_BLOCKED_TEMPLATE_TEXT',
                      :text
                    )

                    {
                      'application/json' => json,
                      'text/html' => html,
                      'text/plain' => text,
                    }
                  end
                  o.setter do |v|
                    next if v.nil?

                    # TODO: should merge with o.default to allow overriding only one mime type

                    v.each do |k, w|
                      case w
                      when :json, :html, :text
                        next
                      when String, Pathname
                        next if File.exist?(w.to_s)

                        raise(ArgumentError, "appsec.templates.#{k}: file not found: #{w}")
                      else
                        raise ArgumentError, "appsec.templates.#{k}: unexpected value: #{w.inspect}"
                      end
                    end
                  end
                end
              end

              settings :track_user_events do
                option :enabled do |o|
                  o.default true
                  o.type :bool
                  o.env 'DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING'
                  o.env_parser do |env_value|
                    if env_value == 'disabled'
                      false
                    else
                      APPSEC_VALID_TRACK_USER_EVENTS_ENABLED_VALUES.include?(env_value.strip.downcase)
                    end
                  end
                end

                option :mode do |o|
                  o.type :string
                  o.env 'DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING'
                  o.default 'safe'
                  o.setter do |v|
                    if APPSEC_VALID_TRACK_USER_EVENTS_MODE.include?(v)
                      v
                    elsif v == 'disabled'
                      'safe'
                    else
                      Datadog.logger.warn(
                        'The appsec.track_user_events.mode value provided is not supported.' \
                        'Supported values are: safe | extended.' \
                        'Using default value `safe`'
                      )
                      'safe'
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
