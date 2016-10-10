require 'ddtrace/tracer'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record'
require 'ddtrace/contrib/rails/active_support'

module Datadog
  module Instrument
    # some stuff
    module RailsFramework
      def self.init_plugin(config)
        # tracer defaults
        default_config = {
          enabled: true,
          default_service: 'rails-app',
          tracer: Datadog::Tracer.new()
        }

        # merge and update Rails configurations
        user_config = config[:config].datadog_trace rescue {}
        datadog_config = default_config.merge(user_config)
        Rails.configuration.datadog_trace = datadog_config

        # TODO[manu]: set default service details

        # auto-instrument the code
        ActiveSupport::Notifications.subscribe('start_processing.action_controller') { |*args| start_processing(*args) }
        ActiveSupport::Notifications.subscribe('start_render_template.action_view') { |*args| start_render_template(*args) }
        ActiveSupport::Notifications.subscribe('start_render_partial.action_view') { |*args| start_render_partial(*args) }
        ActiveSupport::Notifications.subscribe('render_template.action_view') { |*args| render_template(*args) }
        ActiveSupport::Notifications.subscribe('render_partial.action_view') { |*args| render_partial(*args) }
        ActiveSupport::Notifications.subscribe('sql.active_record') { |*args| sql(*args) }
        ActiveSupport::Notifications.subscribe('process_action.action_controller') { |*args| process_action(*args) }
        ActiveSupport::Notifications.subscribe('cache_read.active_support') { |*args| cache_read(*args) }
        ActiveSupport::Notifications.subscribe('cache_write.active_support') { |*args| cache_write(*args) }
        ActiveSupport::Notifications.subscribe('cache_delete.active_support') { |*args| cache_delete(*args) }
      end
    end
  end
end
