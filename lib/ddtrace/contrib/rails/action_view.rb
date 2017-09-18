require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'rails.render_template' and 'rails.render_partial' spans.
      module ActionView
        def self.instrument
          # patch Rails core components
          Datadog::RailsRendererPatcher.patch_renderer()

          # subscribe when the template rendering starts
          ::ActiveSupport::Notifications.subscribe('start_render_template.action_view') do |*args|
            start_render_template(*args)
          end

          # subscribe when the template rendering has been processed
          ::ActiveSupport::Notifications.subscribe('finish_render_template.action_view') do |*args|
            finish_render_template(*args)
          end

          # subscribe when the partial rendering starts
          ::ActiveSupport::Notifications.subscribe('start_render_partial.action_view') do |*args|
            start_render_partial(*args)
          end

          # subscribe when the partial rendering has been processed
          ::ActiveSupport::Notifications.subscribe('render_partial.action_view') do |*args|
            render_partial(*args)
          end
        end

        def self.get_key(f)
          'datadog_actionview_' + f
        end

        def self.start_render_template(_name, _start, _finish, _id, payload)
          # retrieve the tracing context
          tracing_context = payload.fetch(:tracing_context)

          # create a new Span and add it to the tracing context
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.trace('rails.render_template', span_type: Datadog::Ext::HTTP::TEMPLATE)
          tracing_context[:dd_rails_template_span] = span
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end

        def self.finish_render_template(_name, _start, _finish, _id, payload)
          # retrieve the tracing context and the latest active span
          tracing_context = payload.fetch(:tracing_context)
          span = tracing_context[:dd_rails_template_span]
          return unless span && !span.finished?

          # finish the tracing and update the execution time
          begin
            template_name = tracing_context[:template_name]
            layout = tracing_context[:layout]
            exception = tracing_context[:exception]

            span.set_tag('rails.template_name', template_name) if template_name
            span.set_tag('rails.layout', layout) if layout
            span.set_error(exception) if exception
          ensure
            span.finish()
          end
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
            span.set_error(payload[:exception]) if payload[:exception]
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
