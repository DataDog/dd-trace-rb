module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActionView
        def self.instrument
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

        def self.start_render_template(*)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          tracer.trace('rails.render_template')
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end

        def self.start_render_partial(*)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          tracer.trace('rails.render_partial')
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end

        def self.render_template(_name, start, finish, _id, payload)
          # finish the tracing and update the execution time
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.buffer.get
          # TODO: this should be normalized someway
          span.set_tag('rails.template_name', payload.fetch(:identifier))
          span.set_tag('rails.layout', payload.fetch(:layout))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end

        def self.render_partial(_name, start, finish, _id, payload)
          # finish the tracing and update the execution time
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.buffer.get
          # TODO: this should be normalized someway
          span.set_tag('rails.template_name', payload.fetch(:identifier))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end
      end
    end
  end
end
