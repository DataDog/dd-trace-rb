require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/mongodb/ext'
require 'ddtrace/contrib/mongodb/instrumentation'

module Datadog
  module Contrib
    module MongoDB
      # Patcher enables patching of 'mongo' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:mongo)
        end

        def patch
          do_once(:mongo) do
            begin
              ::Mongo::Client.send(:include, Instrumentation)
              ::Mongo::Address.send(:include, Instrumentation)
              add_mongo_monitoring
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply MongoDB integration: #{e}")
            end
          end
        end

        def add_mongo_monitoring
          # Subscribe to all COMMAND queries with our subscriber class
          ::Mongo::Monitoring::Global.subscribe(::Mongo::Monitoring::COMMAND, MongoCommandSubscriber.new)
        end
      end
    end
  end
end
