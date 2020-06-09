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
              super.tap do
                # Emit a metric
                Datadog.health_metrics.instrumentation_patched(1, tags: default_tags)
              end
            rescue StandardError => e
              on_patch_error(e)
            end
          end
        end

        # Processes patching errors. This default implementation logs the error and reports relevant metrics.
        # @param e [Exception]
        def on_patch_error(e)
          # Log the error
          Datadog.logger.error("Failed to apply #{patch_name} patch. Cause: #{e} Location: #{e.backtrace.first}")

          # Emit a metric
          tags = default_tags
          tags << "error:#{e.class.name}"

          Datadog.health_metrics.error_instrumentation_patch(1, tags: tags)
        end

        private

        def default_tags
          ["patcher:#{patch_name}"].tap do |tags|
            tags << "target_version:#{target_version}" if respond_to?(:target_version) && !target_version.nil?
          end
        end
      end
    end
  end
end
