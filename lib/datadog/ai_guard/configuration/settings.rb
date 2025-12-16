# frozen_string_literal: true

require_relative "ext"

module Datadog
  module AIGuard
    module Configuration
      # AI Guard specific settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            # AI Guard specific configurations.
            # @public_api
            settings :ai_guard do
              # Enable AI Guard.
              #
              # You can use this option to skip calls to AI Guard API without having to remove library as a whole.
              #
              # @default `DD_AI_GUARD_ENABLED`, otherwise `false`
              # @return [Boolean]
              option :enabled do |o|
                o.type :bool
                o.env Ext::ENV_AI_GUARD_ENABLED
                o.default false
              end

              # AI Guard API endpoint path.
              #
              # @default `DD_AI_GUARD_ENDPOINT`, otherwise /api/v2/ai-guard
              # @return [String, nil]
              option :endpoint do |o|
                o.type :string, nilable: true
                o.env Ext::ENV_AI_GUARD_ENDPOINT
                o.default "/api/v2/ai-guard"

                o.setter do |value|
                  value.to_s.delete_suffix("/")
                end
              end

              # Datadog Application key.
              #
              # @default `DD_AI_GUARD_APP_KEY` environment variable, otherwise `nil`
              # @return [String, nil]
              option :app_key do |o|
                o.type :string, nilable: true
                o.env Ext::ENV_APP_KEY
              end

              # Request timeout in milliseconds.
              #
              # @default `DD_AI_GUARD_TIMEOUT`, otherwise 10 000 ms
              # @return [Integer]
              option :timeout_ms do |o|
                o.type :int
                o.env Ext::ENV_AI_GUARD_TIMEOUT
                o.default 10_000
                o.setter do |v|
                  Datadog::Core::Utils::Duration.call(v.to_s, base: :us)
                end
              end

              # Maximum content size in bytes.
              # Content that exceeds the maximum allowed size is truncated before being sent to the AI Guard API.
              #
              # @default `DD_AI_GUARD_MAX_CONTENT_SIZE`, otherwise 524 228 bytes
              # @return [Integer]
              option :max_content_size_bytes do |o|
                o.type :int
                o.env Ext::ENV_AI_GUARD_MAX_CONTENT_SIZE
                o.default 512 * 1024
              end

              # Maximum amount of messages.
              # Older messages are omitted once the maximum message limit is reached.
              #
              # @default `DD_AI_GUARD_MAX_MESSAGES_LENGTH`, otherwise 16 messages
              # @return [Integer]
              option :max_messages_length do |o|
                o.type :int
                o.env Ext::ENV_AI_GUARD_MAX_MESSAGES_LENGTH
                o.default 16
              end
            end
          end
        end
      end
    end
  end
end
