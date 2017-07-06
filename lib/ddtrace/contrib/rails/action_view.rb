require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActionView
        def self.instrument
          # patch Rails core components
          Datadog::RailsPatcher.patch_renderer()

          # subscribe when the template rendering starts
          ::ActiveSupport::Notifications.subscribe('start_render_template.action_view') do |*args|
            start_render_template(*args)
          end

          # subscribe when the partial rendering starts
          ::ActiveSupport::Notifications.subscribe('start_render_partial.action_view') do |*args|
            start_render_partial(*args)
          end

          # subscribe when the template rendering has been processed
          ::ActiveSupport::Notifications.subscribe('render_template.action_view') do |*args|
            render_template(*args)
          end

          # subscribe when the partial rendering has been processed
          ::ActiveSupport::Notifications.subscribe('render_partial.action_view') do |*args|
            render_partial(*args)
          end
        end

        def self.get_key(f)
          'datadog_actionview_' + f
        end

        def self.start_render_template(*)
          key = get_key('render_template')
          return if Thread.current[key]

          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          type = Datadog::Ext::HTTP::TEMPLATE
          tracer.trace('rails.render_template', span_type: type)

          Thread.current[key] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.start_render_partial(*)
          key = get_key('render_partial')
          return if Thread.current[key]

          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          type = Datadog::Ext::HTTP::TEMPLATE
          tracer.trace('rails.render_partial', span_type: type)

          Thread.current[key] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.render_template(_name, start, finish, _id, payload)
          key = get_key('render_template')
          return unless Thread.current[key]
          Thread.current[key] = false

          # finish the tracing and update the execution time
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          return unless span

          begin
            template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(payload.fetch(:identifier))
            span.set_tag('rails.template_name', template_name)
            span.set_tag('rails.layout', payload.fetch(:layout))

            if payload[:exception]
              error = payload[:exception]
              span.status = 1
              span.set_tag(Datadog::Ext::Errors::TYPE, error[0])
              span.set_tag(Datadog::Ext::Errors::MSG, error[1])
            end
          ensure
            span.start_time = start
            span.finish(finish)
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.render_partial(_name, start, finish, _id, payload)
          key = get_key('render_partial')
          return unless Thread.current[key]
          Thread.current[key] = false

          # finish the tracing and update the execution time
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          return unless span

          begin
            template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(payload.fetch(:identifier))
            span.set_tag('rails.template_name', template_name)

            if payload[:exception]
              error = payload[:exception]
              span.status = 1
              span.set_tag(Datadog::Ext::Errors::TYPE, error[0])
              span.set_tag(Datadog::Ext::Errors::MSG, error[1])
            end
          ensure
            span.start_time = start
            span.finish(finish)
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
