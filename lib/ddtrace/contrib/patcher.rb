require 'ddtrace/patcher'

module Datadog
  module Contrib
    # Common behavior for patcher modules
    module Patcher
      def self.included(base)
        base.send(:include, Datadog::Patcher)

        base.singleton_class.send(:prepend, CommonMethods)
        base.send(:prepend, CommonMethods) if base.class == Class
      end

      # Prepended instance methods for all patchers
      module CommonMethods
        def patch_name
          self.class != Class && self.class != Module ? self.class.name : name
        end

        def patched?
          done?(:patch)
        end

        def patch
          return unless defined?(super)

          do_once(:patch) do
            begin
              super
            rescue StandardError => e
              Datadog::Tracer.log.error("Failed to apply #{patch_name} patch. Cause: #{e} Location: #{e.backtrace.first}")
            end
          end
        end
      end
    end
  end
end
