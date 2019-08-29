require 'ddtrace/contrib/resque/utils'
require 'resque/plugin'

module Datadog
  module Contrib
    module Resque
      module Job
        def perform
          pin = Datadog::Pin.get_from(::Resque)
          return super unless pin && pin.enabled?

          return super unless has_payload_class? && !payload_class.class_variable_defined?(:@@__datadog_patched)

          job = self
          payload_class.class_eval do
            @@__datadog_patched = true

            singleton_class.class_eval do

              prepend(
                Module.new do
                  job.before_hooks.each do |hook_name|
                    define_method(hook_name, Utils.hook_wrapper(hook_name, Ext::SPAN_JOB_BEFORE_HOOK))
                  end

                  job.after_hooks.each do |hook_name|
                    define_method(hook_name, Utils.hook_wrapper(hook_name, Ext::SPAN_JOB_AFTER_HOOK))
                  end

                  job.failure_hooks.each do |hook_name|
                    define_method(hook_name, Utils.hook_wrapper(hook_name, Ext::SPAN_JOB_FAILURE_HOOK))
                  end

                  job.around_hooks.each do |hook_name|
                    define_method(hook_name) do |*args, &block|
                      pin = Datadog::Pin.get_from(::Resque)
                      return super(*args) unless pin && pin.enabled?

                      pin.tracer.trace(Ext::SPAN_JOB_AROUND_HOOK, service: pin.service_name) do |span|
                        span.resource = "#{self.name}.#{hook_name}"
                        return super(*args, &block)
                      end
                    end
                  end

                  define_method(:perform, Utils.hook_wrapper('perform', Ext::SPAN_JOB_PERFORM))
                end
              )
            end
          end

          super
        end
      end
    end
  end
end
