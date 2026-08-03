# frozen_string_literal: true

require "set"

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Quantize contains Redis-specific resource quantization tools.
        module Quantize
          PLACEHOLDER = "?"
          TOO_LONG_MARK = "..."
          VALUE_MAX_LEN = 50
          CMD_MAX_LEN = 500

          AUTH_COMMANDS = %w[AUTH auth].freeze

          CONNECTION_SETUP_COMMANDS = Set.new(%w[HELLO]).freeze
          CLIENT_CONNECTION_SETUP_SUBCOMMANDS = Set.new(%w[SETINFO SETNAME]).freeze

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
            Datadog.logger.debug("non formattable Redis arg #{str}: #{e.class}: #{e.message}")
            PLACEHOLDER
          end

          def format_command_args(command_args)
            command_args = resolve_command_args(command_args)
            return "AUTH ?" if auth_command?(command_args) || hello_auth_command?(command_args)

            verb, *args = command_args.map { |x| format_arg(x) }
            Core::Utils.truncate("#{verb.upcase} #{args.join(" ")}", CMD_MAX_LEN, TOO_LONG_MARK)
          end

          def get_verb(command_args)
            return unless command_args.is_a?(Array)

            return get_verb(command_args.first) if command_args.first.is_a?(Array)

            return "AUTH" if hello_auth_command?(command_args)

            verb = command_args.first.to_s.upcase
            return verb unless MULTI_VERB_COMMANDS.include?(verb) && command_args[1]

            "#{verb} #{command_args[1]}"
          end

          def auth_command?(command_args)
            return false unless command_args.is_a?(Array) && !command_args.empty?

            verb = command_args.first.to_s
            AUTH_COMMANDS.include?(verb)
          end

          # Identifies a RESP3 `HELLO ... AUTH user pass` handshake command, which embeds
          # credentials the same way a standalone `AUTH` command does and must be redacted
          # (and kept visible as its own span) rather than treated as a silent connection
          # bootstrap command.
          def hello_auth_command?(command_args)
            return false unless command_args.is_a?(Array) && !command_args.empty?

            # `redis-client` always emits this as `["HELLO", "3", "AUTH", username, password]` — check
            # the fixed "AUTH" keyword position only, never the username/password values themselves,
            # since those are untrusted, possibly-binary bulk strings that `#upcase` can raise on.
            command_args.first.to_s.upcase == "HELLO" && command_args[2].to_s.upcase == "AUTH"
          end

          # Identifies protocol-level connection bootstrap commands (`HELLO`, `CLIENT SETINFO`,
          # `CLIENT SETNAME`) that `redis-client` sends as part of its per-connection handshake,
          # so they can be excluded from pipeline resource naming. A `HELLO` carrying `AUTH`
          # credentials is excluded from this so authentication remains visible as its own span.
          def connection_setup_command?(command_args)
            command_args = resolve_command_args(command_args)
            return false unless command_args.is_a?(Array) && !command_args.empty?
            return false if hello_auth_command?(command_args)

            verb = command_args.first.to_s.upcase
            return true if CONNECTION_SETUP_COMMANDS.include?(verb)

            verb == "CLIENT" && CLIENT_CONNECTION_SETUP_SUBCOMMANDS.include?(command_args[1].to_s.upcase)
          end

          # Unwraps command array when Redis is called with the following syntax:
          #   redis.call([:cmd, 'arg1', ...])
          def resolve_command_args(command_args)
            return command_args.first if command_args.is_a?(Array) && command_args.first.is_a?(Array)

            command_args
          end

          private_class_method :auth_command?, :hello_auth_command?, :resolve_command_args
        end
      end
    end
  end
end
