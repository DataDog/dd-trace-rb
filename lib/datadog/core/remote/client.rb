# frozen_string_literal: true

require 'securerandom'

require_relative 'configuration'
require_relative 'dispatcher'

module Datadog
  module Core
    module Remote
      # Client communicates with the agent and sync remote configuration
      class Client
        attr_reader :transport, :repository, :id, :dispatcher

        def initialize(transport, repository: Configuration::Repository.new)
          @transport = transport

          @repository = repository
          @id = SecureRandom.uuid
          @dispatcher = Dispatcher.new
          register_receivers
        end

        # rubocop:disable Metrics/AbcSize
        def sync
          response = transport.send_config(payload)

          if response.ok?
            # when response is completely empty, do nothing as in: leave as is
            return if response.empty?

            paths = response.client_configs.map do |path|
              Configuration::Path.parse(path)
            end

            targets = Configuration::TargetMap.parse(response.targets)

            contents = Configuration::ContentList.parse(response.target_files)

            # TODO: sometimes it can strangely be so that paths.empty?
            # TODO: sometimes it can strangely be so that targets.empty?

            changes = repository.transaction do |current, transaction|
              # paths to be removed: previously applied paths minus ingress paths
              (current.paths - paths).each { |p| transaction.delete(p) }

              # go through each ingress path
              paths.each do |path|
                # match target with path
                target = targets[path]

                # abort entirely if matching target not found
                raise SyncError, "no target for path '#{path}'" if target.nil?

                # new paths are not in previously applied paths
                new = !current.paths.include?(path)

                # updated paths are in previously applied paths
                # but the content hash changed
                changed = current.paths.include?(path) && !current.contents.find_content(path, target)

                # skip if unchanged
                same = !new && !changed

                next if same

                # match content with path and target
                content = contents.find_content(path, target)

                # abort entirely if matching content not found
                raise SyncError, "no valid content for target at path '#{path}'" if content.nil?

                # to be added or updated << config
                # TODO: metadata (hash, version, etc...)
                transaction.insert(path, target, content) if new
                transaction.update(path, target, content) if changed
              end

              # save backend opaque backend state
              transaction.set(opaque_backend_state: targets.opaque_backend_state)
              transaction.set(targets_version: targets.version)

              # upon transaction end, new list of applied config + metadata (add, change, remove) will be saved
              # TODO: also remove stale config (matching removed) from cache (client configs is exhaustive list of paths)
            end

            dispatcher.dispatch(changes, repository)
          else
            raise SyncError, "unexpected transport response: #{response.inspect}"
          end

          # TODO: dispatch config updates to listeners
        end
        # rubocop:enable Metrics/AbcSize

        class SyncError < StandardError; end

        private

        def payload
          state = repository.state

          {
            client: {
              state: {
                root_version: state.root_version,
                targets_version: state.targets_version,
                config_states: state.config_states,
                has_error: state.has_error,
                error: state.error,
                backend_client_state: state.opaque_backend_state,
              },
              id: id,
              products: products,
              is_tracer: true,
              is_agent: false,
              client_tracer: {
                runtime_id: Core::Environment::Identity.id,
                language: Core::Environment::Identity.lang,
                tracer_version: Core::Environment::Identity.tracer_version,
                service: Datadog.configuration.service,
                env: Datadog.configuration.env,
                # app_version: app_version, # TODO: I don't know what this is
                tags: [], # TODO: add nice tags!
              },
              # base64 is needed otherwise the Go agent fails with an unmarshal error
              capabilities: Base64.encode64(capabilities_binary).chomp,
            },
            cached_target_files: [
              # TODO: to be implemented once we cache configuration content
              # {
              #   path: '',
              #   length: 0,
              #   hashes: '';
              # }
            ],
          }
        end

        # TODO: this is serialization of capabilities, it should go in the request serializer/encoder
        CAP_ASM_ACTIVATION                = 1 << 1 # Remote activation via ASM_FEATURES product
        CAP_ASM_IP_BLOCKING               = 1 << 2 # accept IP blocking data from ASM_DATA product
        CAP_ASM_DD_RULES                  = 1 << 3 # read ASM rules from ASM_DD product
        CAP_ASM_EXCLUSIONS                = 1 << 4 # exclusion filters (passlist) via ASM product
        CAP_ASM_REQUEST_BLOCKING          = 1 << 5 # can block on request info
        CAP_ASM_RESPONSE_BLOCKING         = 1 << 6 # can block on response info
        CAP_ASM_USER_BLOCKING             = 1 << 7 # accept user blocking data from ASM_DATA product
        CAP_ASM_CUSTOM_RULES              = 1 << 8 # accept custom rules
        CAP_ASM_CUSTOM_BLOCKING_RESPONSE  = 1 << 9 # supports custom http code or redirect sa blocking response

        # TODO: this should go in the AppSec namespace
        # TODO: condition by active configuration
        def products
          [
            'ASM_DD',       # Datadog employee issued configuration
            'ASM',          # customer issued configuration (rulesets, passlist...)
            'ASM_FEATURES', # capabilities
            'ASM_DATA',     # config files (IP addresses or users for blocking)
          ]
        end

        CAPABILITIES = [
          CAP_ASM_IP_BLOCKING,
          CAP_ASM_USER_BLOCKING,
          CAP_ASM_CUSTOM_RULES,
          CAP_ASM_EXCLUSIONS,
          CAP_ASM_REQUEST_BLOCKING,
          CAP_ASM_RESPONSE_BLOCKING,
          CAP_ASM_DD_RULES,
        ].freeze

        # TODO: as a declaration, this should go in the AppSec namepsace
        # TODO: as serialization, this should go in the request serializer/encoder
        # TODO: condition by active configuration
        def capabilities
          CAPABILITIES.reduce(:|)
        end

        # TODO: this is serialization of capabilities, it should go in the request serializer/encoder
        def capabilities_binary
          cap_to_hexs = capabilities.to_s(16).tap { |s| s.size.odd? && s.prepend('0') }.scan(/\h\h/)
          cap_to_hexs.each_with_object([]) { |hex, acc| acc << hex }.map { |e| e.to_i(16) }.pack('C*')
        end

        def register_receivers
          matcher = Dispatcher::Matcher::Product.new(products)

          dispatcher.receivers << Dispatcher::Receiver.new(matcher) do |_repository, changes|
            changes.each { |change| Datadog.logger.debug { "remote config change: #{change.path.inspect}" } }
          end
        end
      end
    end
  end
end
