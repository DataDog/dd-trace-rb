# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kernel
        def require(name)
          # Returns `true` if file was loaded by this `super` operation.
          # If it was already loaded, returns `false`.
          # If `super` errs, it will raise an exception.
          just_loaded = super

          @@dd_instance.require(name) if just_loaded

          just_loaded
        end

        class Instance
          def initialize
            @on_require = {}
          end

          def require(name)
            if @on_require.include?(name)
              Datadog.logger.debug { "Gem '#{name}' loaded. Invoking callback." }

              @on_require[name].call
            end
          rescue => e
            Datadog.logger.debug do
              "Failed to execute callback for gem '#{name}': #{e.class.name} #{e.message} at #{Array(e.backtrace).join("\n")}"
            end
          end

          def on_require(gem, &block)
            @on_require[gem] = block
          end
        end

        class << self
          def on_require(gem, &block)
            @@dd_instance.on_require(gem, &block)
          end

          def patch!
            @@DD_PATCH_ONLY_ONCE.run do
              @@dd_instance = Instance.new
              ::Kernel.prepend(self)
            end
          end

          @@DD_PATCH_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new

          private

          # Only use this method for resetting patching between test runs.
          def reset_patch!
            @@dd_instance = nil
            @@DD_PATCH_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new
          end
        end
      end
    end
  end
end

