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

        def receivers(telemetry)
          receiver do |repository, changes|
            # DEV: Filter our by product. Given it will be very common
            # DEV: we can filter this out before we receive the data in this method.
            # DEV: Apply this refactor to AppSec as well if implemented.

            component = DI.component
            # We should always have a non-nil DI component here, because we
            # only add DI product to remote config request if DI is enabled.
            # Ideally, we should be injected with the DI component here
            # rather than having to retrieve it from global state.
            # If the component is nil for some reason, we also don't have a
            # logger instance to report the issue.
            if component
              changes.each do |change|
                case change.type
                when :insert
                  add_probe(change.content, component)
                when :update
                  # We do not implement updates at the moment, remove the
                  # probe and reinstall.
                  remove_probe(change.content, component)
                  add_probe(change.content, component)
                when :delete
                  remove_probe(change.previous, component)
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
            component.telemetry&.report(exc, description: "Line probe is targeting a loaded file that is not in code tracker")

            payload = component.probe_notification_builder.build_errored(probe, exc)
            component.probe_notifier_worker.add_status(payload, probe: probe)

            # If a probe fails to install, we will mark the content
            # as errored. On subsequent remote configuration application
            # attemps, probe manager will raise the "previously errored"
            # exception and we'll rescue it here, again marking the
            # content as errored but with a somewhat different exception
            # message.
            # TODO assert content state (errored for this example)
            content.errored("Error applying dynamic instrumentation configuration: #{exc.class.name} #{exc.message}")
          rescue => exc
            raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

            component.logger.debug { "di: unhandled exception adding #{probe.type} probe at #{probe.location} (#{probe.id}) in DI remote receiver: #{exc.class}: #{exc}" }
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
            content.errored("Error applying dynamic instrumentation configuration: #{exc.class.name} #{exc.message}")
          end

          # Important: even if processing fails for this probe config,
          # we need to note it as being current so that we do not
          # try to remove instrumentation that is still supposed to be
          # active.
          #current_probe_ids[probe_spec.fetch('id')] = true
        rescue => exc
          raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

          component.logger.debug { "di: unhandled exception handling a probe in DI remote receiver: #{exc.class}: #{exc}" }
          component.telemetry&.report(exc, description: "Unhandled exception handling probe in DI remote receiver")

          # TODO assert content state (errored for this example)
          content.errored("Error applying dynamic instrumentation configuration: #{exc.class.name} #{exc.message}")
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

          component.logger.debug { "di: unhandled exception removing probes in DI remote receiver: #{exc.class}: #{exc}" }
          component.telemetry&.report(exc, description: "Unhandled exception removing probes in DI remote receiver")
        end

        def parse_content(content)
          JSON.parse(content.data)
        end
      end
    end
  end
end
