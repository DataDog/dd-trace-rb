# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # N+1 query detection reporting
        module Bullet
          # Bullet's offending stack finder utility.
          # Used to backfill the missing stack trace in Bullet::Detector::CounterCache errors.
          StackFilter = Class.new { extend ::Bullet::StackTraceFilter }

          # Bullet's NotificationCollector receives every bullet error at the offending site.
          # This allows us to attribute the error to the closest enclosing span.
          module NotificationCollector
            def add(value)
              return super unless Datadog.configuration.tracing[:active_record][:report_bullet]

              active_span = Datadog::Tracing.active_span
              if active_span && !active_span.has_error? # Do not override an application error, if present
                callers = value.instance_variable_get(:@callers) || StackFilter.caller_in_project

                # Try to match the original Bullet error reporting as much as possible.
                # Users will be immediately familiar with the output.
                active_span.set_error(['Bullet::Notification::UnoptimizedQueryError',
                                       "#{value.title}\n#{value.body}",
                                       callers])
              end

              super
            end
          end

          def self.patch!
            ::Bullet::NotificationCollector.prepend(NotificationCollector)
          end
        end
      end
    end
  end
end
