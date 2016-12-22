require 'ddtrace'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record'
require 'ddtrace/contrib/rails/active_support'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # TODO[manu]: write docs
    module Rails
      # TODO[manu]: write docs
      module Framework
        # the default configuration
        DEFAULT_CONFIG = {
          enabled: true,
          auto_instrument: true,
          default_service: 'rails-app',
          default_cache_service: 'rails-cache',
          template_base_path: 'views/',
          tracer: Datadog.tracer
        }.freeze

        # configure Datadog settings
        def self.configure(config)
          # tracer defaults
          # merge default configurations with users settings
          user_config = config[:config].datadog_trace rescue {}
          datadog_config = DEFAULT_CONFIG.merge(user_config)
          datadog_config[:tracer].enabled = datadog_config[:enabled]

          # set default service details
          datadog_config[:tracer].set_service_info(
            datadog_config[:default_service],
            'rails',
            Datadog::Ext::AppTypes::WEB
          )
          datadog_config[:tracer].set_service_info(
            datadog_config[:default_cache_service],
            'rails',
            Datadog::Ext::AppTypes::CACHE
          )

          # set default database service details and store it in the configuration
          adapter_name = ::ActiveRecord::Base.connection_config[:adapter]
          adapter_name = Datadog::Contrib::Rails::Utils.normalize_vendor(adapter_name)
          database_service = datadog_config.fetch(:default_database_service, adapter_name)
          datadog_config[:default_database_service] = database_service
          datadog_config[:tracer].set_service_info(
            database_service,
            adapter_name,
            Datadog::Ext::AppTypes::DB
          )

          # update global configurations
          ::Rails.configuration.datadog_trace = datadog_config
        end

        # automatically instrument all Rails component
        def self.auto_instrument
          return unless ::Rails.configuration.datadog_trace[:auto_instrument]
          Datadog::Tracer.log.info('Detected Rails >= 3.x. Enabling auto-instrumentation for core components.')
          Datadog::Contrib::Rails::ActionController.instrument()
          Datadog::Contrib::Rails::ActionView.instrument()
          Datadog::Contrib::Rails::ActiveRecord.instrument()
          Datadog::Contrib::Rails::ActiveSupport.instrument()

          # by default, Rails 3 doesn't instrument the cache system
          return unless ::Rails::VERSION::MAJOR.to_i == 3
          ::ActiveSupport::Cache::Store.instrument = true
        end
      end
    end
  end
end
