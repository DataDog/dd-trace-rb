# frozen_string_literal: true

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
        PRODUCT = 'LIVE_DEBUGGING'

        def products
          # TODO: do not send our product on unsupported runtimes
          # (Ruby 2.5 / JRuby)
          [PRODUCT]
        end

        def capabilities
          []
        end

        def handle_rc_enablement(enabled)
          component = Datadog.send(:components).dynamic_instrumentation
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
              reason = DI.unsupported_reason
              Datadog.logger.warn(
                "di: cannot enable dynamic instrumentation via remote configuration: " \
                "#{reason || "DI component was not built at startup"}"
              )
            end
            return
          end

          if enabled
            if explicitly_disabled?
              Datadog.logger.warn(
                "di: ignoring implicit enablement signal from remote configuration " \
                "because DD_DYNAMIC_INSTRUMENTATION_ENABLED is explicitly set to false. " \
                "To allow remote enablement, unset DD_DYNAMIC_INSTRUMENTATION_ENABLED."
              )
              return
            end
            # Same guard as Components#startup! — DI.activate_tracking is only
            # defined when di/base.rb is loaded (Ruby >= 2.6). On 2.5 the
            # component is always nil so we never reach this in production;
            # the guard is for tests that stub component presence.
            DI.activate_tracking if DI.respond_to?(:activate_tracking)
            component.start!
          else
            component.stop!
          end
        rescue => e
          Datadog.logger.debug { "di: error handling implicit enablement: #{e.class}: #{e.message}" }
          Datadog.send(:components).telemetry&.report(e, description: "Error handling DI implicit enablement")
        end

        def explicitly_disabled?
          settings = Datadog.configuration
          !settings.dynamic_instrumentation.options[:enabled].default_precedence? &&
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
                  add_probe(change.content, component) # steep:ignore NoMethod
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
          rescue => exc
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
          #current_probe_ids[probe_spec.fetch('id')] = true
        rescue => exc
          raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

          component.logger.debug { "di: unhandled exception handling a probe in DI remote receiver: #{exc.class}: #{exc.message}" }
          component.telemetry&.report(exc, description: "Unhandled exception handling probe in DI remote receiver")

          # TODO assert content state (errored for this example)
          content.errored("Error applying dynamic instrumentation configuration: #{exc.class}: #{exc.message}")
        end

        # This method does not mark +previous_content+ as succeeded or errored,
        # because that content is from a previous RC response and has already
        # been marked. Removal of probes happens when an RC entry disappears,
        # as such there is nothing to mark.
        def remove_probe(previous_content, component)
          # TODO test exception capture
          probe_spec = parse_content(previous_content)
          probe_id = probe_spec.fetch('id')
          component.probe_manager.remove_probe(probe_id)
        rescue => exc
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
