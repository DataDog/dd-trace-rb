# frozen_string_literal: true

require 'set'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Quantize contains Redis-specific resource quantization tools.
        module Quantize
          PLACEHOLDER = '?'
          TOO_LONG_MARK = '...'
          VALUE_MAX_LEN = 50
          CMD_MAX_LEN = 500

          AUTH_COMMANDS = %w[AUTH auth].freeze
          MIGRATE_COMMANDS = %w[MIGRATE migrate].freeze
          HELLO_COMMANDS = %w[HELLO hello].freeze
          KEYS_COMMANDS = %w[KEYS keys].freeze

          MULTI_VERB_COMMANDS = Set.new(
            %w[
              ACL
              CLIENT
              CLUSTER
              COMMAND
              CONFIG
              DEBUG
              LATENCY
              MEMORY
            ]
          ).freeze

          module_function

          def format_arg(arg)
            str = Core::Utils.utf8_encode(arg, binary: true, placeholder: PLACEHOLDER)
            Core::Utils.truncate(str, VALUE_MAX_LEN, TOO_LONG_MARK)
          rescue => e
            Datadog.logger.debug("non formattable Redis arg #{str}: #{e}")
            PLACEHOLDER
          end

          def format_command_args(command_args)
            command_args = resolve_command_args(command_args)
            obfuscate_auth_args!(command_args)

            verb, *args = command_args.map { |x| format_arg(x) }
            Core::Utils.truncate("#{verb.upcase} #{args.join(" ")}", CMD_MAX_LEN, TOO_LONG_MARK)
          end

          def get_verb(command_args)
            return unless command_args.is_a?(Array)

            return get_verb(command_args.first) if command_args.first.is_a?(Array)

            verb = command_args.first.to_s.upcase
            return verb unless MULTI_VERB_COMMANDS.include?(verb) && command_args[1]

            "#{verb} #{command_args[1]}"
          end

          def obfuscate_auth_args!(command_args)
            return unless command_args.is_a?(Array) && !command_args.empty?

            verb = command_args.first.to_s
            case verb
            when *AUTH_COMMANDS
              command_args.replace(%w[AUTH ?])
            when *HELLO_COMMANDS
              auth_index = command_args.find_index { |arg| AUTH_COMMANDS.include?(arg.to_s) }
              return if auth_index.nil?

              command_args[auth_index + 1] = '?'
              # HELLO was introduced in Redis 6, which always requires username and password.
              # (username can be set to default in case there's only a requirepass mechanism, but it's always here so we can safely use delete_at)
              command_args.delete_at(auth_index + 2)
            when *MIGRATE_COMMANDS
              auth_index = command_args.find_index { |arg| AUTH_COMMANDS.include?(arg.to_s) }
              return if auth_index.nil?

              command_args[auth_index + 1] = '?'
              keys_index = command_args.find_index { |arg| KEYS_COMMANDS.include?(arg.to_s) }
              if auth_index + 2 < (keys_index.nil? ? command_args.length : keys_index)
                # In this case there's both a username and a password
                command_args.delete_at(auth_index + 2)
              end
            end
          end

          # Unwraps command array when Redis is called with the following syntax:
          #   redis.call([:cmd, 'arg1', ...])
          def resolve_command_args(command_args)
            return command_args.first if command_args.is_a?(Array) && command_args.first.is_a?(Array)

            command_args
          end

          private_class_method :obfuscate_auth_args!, :resolve_command_args
        end
      end
    end
  end
end
