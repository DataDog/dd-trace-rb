# frozen_string_literal: true

require 'json'

module Datadog
  module DI
    module ProbeFileLoader
      module_function def load_now_or_later
        if Datadog::Core::Contrib::Rails::Utils.railtie_supported?
          Datadog.logger.debug('di: loading probe_file_loader/railtie')
          require_relative 'probe_file_loader/railtie'
        else
          load_now
        end
      end

      # This method can be called more than once, to attempt to load
      # DI components that depend on third-party libraries after additional
      # dependencies are loaded (or potentially loaded).
      module_function def load_now
        should_propagate = false

        probe_file_path = DATADOG_ENV['DD_DYNAMIC_INSTRUMENTATION_PROBE_FILE']
        if probe_file_path.nil? || probe_file_path.empty?
          return
        end

        # We want to initialize the component tree here if it was not already
        # initialized.
        component = Datadog::DI.component
        return unless component

        begin
          probe_specs = File.open(probe_file_path) do |f|
            # The probe file should contain an array, JSON.parse does not work
            JSON.load(f) # standard:disable Security/JSONLoad
          end

          probe_specs.each do |probe_spec|
            probe = component.parse_probe_spec_and_notify(probe_spec)
            component.logger.debug { "di: received #{probe.type} probe at #{probe.location} (#{probe.id}) via probe file: #{probe_file_path}" }

            begin
              component.probe_manager.add_probe(probe)
            rescue DI::Error::DITargetNotInRegistry => exc
              component.telemetry&.report(exc, description: "Line probe is targeting a loaded file that is not in code tracker")

              payload = component.probe_notification_builder.build_errored(probe, exc)
              component.probe_notifier_worker.add_status(payload)
            rescue => exc
              raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions

              component.logger.debug { "di: unhandled exception adding #{probe.type} probe at #{probe.location} (#{probe.id}) in DI probe file loader: #{exc.class}: #{exc}" }
              component.telemetry&.report(exc, description: "Unhandled exception adding probe in DI probe file loader")

              # TODO test this path
              payload = component.probe_notification_builder.build_errored(probe, exc)
              component.probe_notifier_worker.add_status(payload)
            end
          end
        rescue => exc
          if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions
            should_propagate = true
            raise
          end

          component.logger.debug { "di: unhandled exception handling a probe in DI probe file loader: #{exc.class}: #{exc}" }
          component.telemetry&.report(exc, description: "Unhandled exception handling probe in DI probe file loader")
        end
      rescue
        # We should generally never get here, but if component tree
        # initialization fails for some unexpected reason, don't nuke
        # the customer application.
        #
        # For the same reason, we do not check
        # component.settings.dynamic_instrumentation.internal.propagate_all_exceptions
        # here again, but rely on the local variable storing that value.
        raise if should_propagate
      end
    end
  end
end
