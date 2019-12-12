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

        def target_version
          Integration.version
        end

        def patch
          ::Mongo::Address.send(:include, Instrumentation::Address)
          ::Mongo::Client.send(:include, Instrumentation::Client)
          add_mongo_monitoring
        end

        def add_mongo_monitoring
          # Subscribe to all COMMAND queries with our subscriber class
          ::Mongo::Monitoring::Global.subscribe(::Mongo::Monitoring::COMMAND, MongoCommandSubscriber.new)
        end
      end
    end
  end
end
