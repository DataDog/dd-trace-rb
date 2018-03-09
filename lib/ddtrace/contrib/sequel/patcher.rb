# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module Sequel
      URL = 'sequel.url'.freeze
      METHOD = 'sequel.method'.freeze
      PARAMS = 'sequel.params'.freeze
      BODY = 'sequel.body'.freeze

      SERVICE = 'sequel'.freeze

      # Patcher enables patching of 'sequel/transport' module.
      module Patcher
        include Base
        register_as :sequel, auto_patch: true
        option :service_name, default: SERVICE
        option :tracer, default: Datadog.tracer

        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          if !@patched && (defined?(::Sequel))
            begin
              require 'uri'
              require 'json'
              require 'ddtrace/pin'
              require 'ddtrace/ext/sql'
              require 'ddtrace/ext/app_types'

              patch_sequel_log()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Sequel integration: #{e}")
            end
          end
          @patched
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def patch_sequel_log
          # rubocop:disable Metrics/BlockLength
          ::Sequel::Database.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              service = Datadog.configuration[:sequel][:service_name]
              pin = Datadog::Pin.new(service,
                app: 'sequel',
                app_type: Datadog::Ext::AppTypes::DB,
                tags: {
                  'sequel.db.vendor' => args.first[:adapter],
                  'sequel.db.name' => args.first[:database],
                  'sequel.db.host' => args.first[:host],
                }
              )
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            alias_method :log_exception_without_datadog, :log_exception
            remove_method :log_exception
            def log_exception(exception, message)
              log_exception_without_datadog(exception, message)
              Datadog::Tracer.log.error(exception.message)
            end

            alias_method :log_duration_without_datadog, :log_duration
            remove_method :log_duration
            def log_duration(duration, message)
              finish_time = Time.now
              start_time = finish_time - duration
              pin = Datadog::Pin.get_from(self)
              log_duration_without_datadog(duration, message)

              span_type = Datadog::Ext::SQL::TYPE

              span = pin.tracer.trace(
                "#{self.database_type}.query",
                resource: message,
                service: pin.service,
                span_type: span_type
              )

              span.start_time = start_time
              span.finish(finish_time)
            end
          end
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
