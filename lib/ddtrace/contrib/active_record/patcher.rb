require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/active_record/configuration'
require 'ddtrace/contrib/active_record/utils'
require 'ddtrace/contrib/active_record/events'

module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      module Patcher
        include Base

        register_as :active_record, auto_patch: false
        option :service_name, depends_on: [:tracer] do |value|
          (value || Utils.adapter_name).tap do |v|
            get_option(:tracer).set_service_info(v, 'active_record', Ext::AppTypes::DB)
          end
        end
        option :databases, default: {} do |value|
          value.tap do
            Configuration.clear_database_settings!
            Configuration.database_settings = value
          end
        end
        option :orm_service_name
        option :tracer, default: Datadog.tracer do |value|
          (value || Datadog.tracer).tap do |v|
            # Make sure to update tracers of all subscriptions
            Events.subscriptions.each do |subscription|
              subscription.tracer = v
            end
          end
        end

        @patched = false

        module_function

        # patched? tells whether patch has been successfully applied
        def patched?
          @patched
        end

        def patch
          if !@patched && defined?(::ActiveRecord)
            begin
              Events.subscribe!
              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Active Record integration: #{e}")
            end
          end

          @patched
        end
      end
    end
  end
end
