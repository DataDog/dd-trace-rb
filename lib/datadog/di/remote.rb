# frozen_string_literal: true

require_relative "fatal_exceptions"

module Datadog
  module DI
    # Provides an interface expected by the core Remote subsystem to
    # receive DI-specific remote configuration.
    #
    # In order to apply (i.e., act on) the configuration, we need the
    # state stored under DI Component. Thus, this module forwards actual
    # configuration application to the ProbeManager associated with the
    # global DI Component.
    #
    # @api private
    module Remote
      class << self
        PRODUCT = "LIVE_DEBUGGING"

        # Declared here (not in Tracing::Remote::CAPABILITIES) so it is
        # registered only with the gated DI block in Capabilities#register:
        # when DI is explicitly disabled, or the runtime cannot run DI
        # (JRuby, Ruby 2.5), that block — including this bit — is skipped.
        # The enable signal itself is delivered in APM_TRACING payloads and
        # routed here by Tracing::Remote.process_config.
        CAPABILITIES = [
          1 << 38, # APM_TRACING_ENABLE_DYNAMIC_INSTRUMENTATION: Implicit DI enablement
        ].freeze

        def products
          [PRODUCT]
        end

        def capabilities
          CAPABILITIES
        end

        # Entry point for the RC-driven DI enable/disable path.
        #
        # Invoked from {Datadog::Tracing::Remote.process_config} when an
        # APM_TRACING payload carries `dynamic_instrumentation_enabled`. Runs
        # on the remote-config thread; never raises.
        #
        # @param enabled [Boolean] desired state from RC: true to start DI,
        #   false to stop it. The `DD_DYNAMIC_INSTRUMENTATION_ENABLED=false`
        #   env var blocks an enable here (see {.explicitly_disabled?}).
        # @param repository [Datadog::Core::Remote::Configuration::Repository, nil]
        #   the RC repository, passed by {Datadog::Tracing::Remote.process_config}
        #   so that a stopped->started transition can reconcile against probes that
        #   were delivered in an earlier poll. nil when called outside the RC
        #   dispatch path (e.g. unit tests), in which case no reconcile happens.
        # @return [void]
        def handle_rc_enablement(enabled, repository = nil)
          # allow_initialization: false because this runs on the remote-config
          # thread (a callback context). The default `true` would synchronously
          # build the entire component tree from the wrong thread if the RC
          # signal lands before Components#initialize completed.
          components = Datadog.send(:components, allow_initialization: false)
          component = components&.dynamic_instrumentation
          unless component
            # The component is nil because Component.build returned nil at
            # startup — a runtime precondition is not met (RC disabled, MRI
            # required, Ruby 2.6+ required, Rails dev env, C extension absent).
            # On disable, silently no-op: RC asking us to turn off something we
            # don't have is fine. On enable, warn with the reason: this is the
            # implicit-enablement counterpart to the warn-on-explicit message
            # at build time. The customer who clicked "create probe" in the UI
            # gets the same visibility a customer who set
            # DD_DYNAMIC_INSTRUMENTATION_ENABLED would have gotten at boot.
            if enabled
              if explicitly_disabled?
                Datadog.logger.warn(
                  "di: cannot enable dynamic instrumentation via remote configuration " \
                  "because DD_DYNAMIC_INSTRUMENTATION_ENABLED is explicitly set to false",
                )
              else
                reason = DI.unsupported_reason
                Datadog.logger.warn(
                  "di: cannot enable dynamic instrumentation via remote configuration: " \
                  "#{reason || "dynamic instrumentation was not initialized at startup"}",
                )
              end
            end
            return
          end

          if enabled
            if explicitly_disabled?
              Datadog.logger.warn(
                "di: ignoring implicit enablement signal from remote configuration " \
                "because DD_DYNAMIC_INSTRUMENTATION_ENABLED is explicitly set to false. " \
                "To allow remote enablement, unset DD_DYNAMIC_INSTRUMENTATION_ENABLED.",
              )
              return
            end
            # component is non-nil here only because Component.build's preconditions
            # passed, which is the same condition under which di/base.rb is loaded
            # and DI.activate_tracking is defined.
            DI.activate_tracking
            was_started = component.started?
            component.start!
            # A probe delivered in an earlier poll while the component was stopped
            # was dropped by #receivers (which ignores changes while !started?) and
            # never entered the probe repository. RC dispatch only re-delivers a
            # config when its content hash changes (Core::Remote::Client#apply_config
            # skips unchanged content), so the probe would otherwise stay dropped
            # until the customer edits it. On the stopped->started transition,
            # reconcile against the current LIVE_DEBUGGING contents so it installs now.
            replay_current_probes(repository, component) if repository && !was_started
          else
            component.stop!
          end
        rescue => e
          Datadog.logger.debug { "di: error handling implicit enablement: #{e.class}: #{e.message}" }
          Datadog.send(:components, allow_initialization: false)&.telemetry&.report(
            e,
            description: "Error handling DI implicit enablement",
          )
        end

        # Symmetric to {DI::Component.explicitly_enabled?} (see there for why
        # using_default? rather than options[:enabled].default_precedence?).
        #
        # Canonical home for the explicit-disable check: it gates
        # {DI::Component.build} and the DI block in
        # {Core::Remote::Client::Capabilities#register}. The latter runs before
        # DI::Component is loaded, so the check lives here on DI::Remote (always
        # required by capabilities.rb) rather than on DI::Component. The
        # `settings` argument lets those startup callers pass the settings being
        # configured; the RC handler omits it and reads the global config.
        #
        # @param settings [Datadog::Core::Configuration::Settings]
        # @return [Boolean] true when the customer set
        #   `DD_DYNAMIC_INSTRUMENTATION_ENABLED=false` (or the programmatic
        #   equivalent), which blocks DI build and RC-driven enablement.
        def explicitly_disabled?(settings = Datadog.configuration)
          !settings.dynamic_instrumentation.using_default?(:enabled) &&
            !settings.dynamic_instrumentation.enabled
        end

        def receivers(telemetry)
          receiver do |repository, changes|
            # DEV: Filter our by product. Given it will be very common
            # DEV: we can filter this out before we receive the data in this method.
            # DEV: Apply this refactor to AppSec as well if implemented.

            component = DI.component
            if component&.started?
              changes.each do |change|
                case change.type
                when :insert
                  # A stopped->started reconcile (#replay_current_probes) may have
                  # installed this probe earlier in the same dispatch — the enable
                  # signal is carried by the Tracing receiver, which runs before the
                  # DI receiver. Skip the redundant install rather than letting
                  # probe_manager raise AlreadyInstrumented and report a false error.
                  unless probe_in_content_known?(change.content, component) # steep:ignore NoMethod
                    add_probe(change.content, component) # steep:ignore NoMethod
                  end
                when :update
                  # We do not implement updates at the moment, remove the
                  # probe and reinstall.
                  remove_probe(change.content, component) # steep:ignore NoMethod
                  add_probe(change.content, component) # steep:ignore NoMethod
                when :delete
                  remove_probe(change.previous, component) # steep:ignore NoMethod
                else
                  # This really should never happen since we generate the
                  # change types in the library.
                  component.logger.debug { "di: unrecognized change type: #{change.type}" }
                end
              end
            end
          end
        end

        def receiver(products = [PRODUCT], &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
        end

        private

        def add_probe(content, component)
          probe_spec = parse_content(content)
          probe = component.parse_probe_spec_and_notify(probe_spec)
          component.logger.debug { "di: received #{probe.type} probe at #{probe.location} (#{probe.id}) via RC" }

          begin
            # TODO test exception capture
            component.probe_manager.add_probe(probe)
            content.applied
          rescue DI::Error::DITargetNotInRegistry => exc
            # Error status is already reported by probe_manager.add_probe,
            # so we don't need to send another error payload here.
            # Just mark the remote config content as errored.
            #
            # If a probe fails to install, we will mark the content
            # as errored. On subsequent remote configuration application
            # attempts, probe manager will raise the "previously errored"
            # exception and we'll rescue it here, again marking the
            # content as errored but with a somewhat different exception
            # message.
            # TODO assert content state (errored for this example)
            content.errored("Error applying dynamic instrumentation configuration: #{exc.class}: #{exc.message}")
          rescue Exception => exc # standard:disable Lint/RescueException
            Datadog::DI.reraise_if_fatal(exc)
            raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

            component.logger.debug { "di: unhandled exception adding #{probe.type} probe at #{probe.location} (#{probe.id}) in DI remote receiver: #{exc.class}: #{exc.message}" }
            component.telemetry&.report(exc, description: "Unhandled exception adding probe in DI remote receiver")

            # TODO test this path
            payload = component.probe_notification_builder.build_errored(probe, exc)
            component.probe_notifier_worker.add_status(payload, probe: probe)

            # If a probe fails to install, we will mark the content
            # as errored. On subsequent remote configuration application
            # attemps, probe manager will raise the "previously errored"
            # exception and we'll rescue it here, again marking the
            # content as errored but with a somewhat different exception
            # message.
            # TODO assert content state (errored for this example)
            content.errored("Error applying dynamic instrumentation configuration: #{exc.class}: #{exc.message}")
          end

          # Important: even if processing fails for this probe config,
          # we need to note it as being current so that we do not
          # try to remove instrumentation that is still supposed to be
          # active.
          # current_probe_ids[probe_spec.fetch('id')] = true
        rescue Exception => exc # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(exc)
          raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

          component.logger.debug { "di: unhandled exception handling a probe in DI remote receiver: #{exc.class}: #{exc.message}" }
          component.telemetry&.report(exc, description: "Unhandled exception handling probe in DI remote receiver")

          # TODO assert content state (errored for this example)
          content.errored("Error applying dynamic instrumentation configuration: #{exc.class}: #{exc.message}")
        end

        # Reconciles the DI probe repository against the LIVE_DEBUGGING configs
        # currently held by the RC repository. Called on the stopped->started
        # transition to install probes that arrived while DI was stopped: those
        # were dropped by {.receivers} and RC will not re-dispatch them because
        # their content hash is unchanged.
        #
        # Probes already tracked by the component (installed, pending, or failed)
        # are skipped, so a probe handled in the same dispatch by {.receivers} is
        # not added twice.
        def replay_current_probes(repository, component)
          repository.contents.each do |content|
            next unless content.path.product == PRODUCT

            begin
              probe_id = parse_content(content)["id"]
            rescue => exc
              component.logger.debug { "di: skipping unparseable LIVE_DEBUGGING content on enable reconcile: #{exc.class}: #{exc.message}" }
              next
            end

            next if probe_id && probe_known?(probe_id, component)

            add_probe(content, component)
          end
        end

        def probe_known?(probe_id, component)
          repo = component.probe_manager.probe_repository
          !!(repo.find_installed(probe_id) ||
            repo.find_pending(probe_id) ||
            repo.find_failed(probe_id))
        end

        # True when the probe carried by +content+ is already tracked by the
        # component. Returns false when the id cannot be determined, so add_probe
        # still runs and reports the parse error through its own handling.
        def probe_in_content_known?(content, component)
          probe_id = parse_content(content)["id"]
          !!(probe_id && probe_known?(probe_id, component))
        rescue => exc
          component.logger.debug { "di: could not check probe id for insert dedup: #{exc.class}: #{exc.message}" }
          false
        end

        # This method does not mark +previous_content+ as succeeded or errored,
        # because that content is from a previous RC response and has already
        # been marked. Removal of probes happens when an RC entry disappears,
        # as such there is nothing to mark.
        def remove_probe(previous_content, component)
          # TODO test exception capture
          probe_spec = parse_content(previous_content)
          probe_id = probe_spec.fetch("id")
          component.probe_manager.remove_probe(probe_id)
        rescue Exception => exc # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(exc)
          raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

          component.logger.debug { "di: unhandled exception removing probes in DI remote receiver: #{exc.class}: #{exc.message}" }
          component.telemetry&.report(exc, description: "Unhandled exception removing probes in DI remote receiver")
        end

        def parse_content(content)
          JSON.parse(content.data)
        end
      end
    end
  end
end
