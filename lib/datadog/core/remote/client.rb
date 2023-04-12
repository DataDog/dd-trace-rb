# frozen_string_literal: true

require 'securerandom'

require_relative 'configuration'
require_relative 'dispatcher'

module Datadog
  module Core
    module Remote
      # Client communicates with the agent and sync remote configuration
      class Client
        class SyncError < StandardError; end

        attr_reader :transport, :repository, :id, :dispatcher

        def initialize(transport, capabilities, repository: Configuration::Repository.new)
          @transport = transport

          @repository = repository
          @id = SecureRandom.uuid
          @dispatcher = Dispatcher.new
          @capabilities = capabilities

          @capabilities.receivers.each do |receiver|
            dispatcher.receivers << receiver
          end
        end

        # rubocop:disable Metrics/AbcSize,Metrics/PerceivedComplexity
        def sync
          # TODO: Skip sync if no capabilities are registered
          response = transport.send_config(payload)

          if response.ok?
            # when response is completely empty, do nothing as in: leave as is
            if response.empty?
              Datadog.logger.debug { 'remote: empty response => NOOP' }

              return
            end

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

            if changes.empty?
              Datadog.logger.debug { 'remote: no changes' }
            else
              dispatcher.dispatch(changes, repository)
            end
          else
            raise SyncError, "unexpected transport response: #{response.inspect}"
          end
        end
        # rubocop:enable Metrics/AbcSize,Metrics/PerceivedComplexity

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
              products: @capabilities.products,
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
              capabilities: @capabilities.base64_capabilities
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
      end
    end
  end
end
