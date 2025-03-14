# frozen_string_literal: true

require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      # Modifies the behavior of the Ruby `Kernel` module
      module Kernel
        class << self
          # Registers a callback for when a gem is required.
          # Invoking it with an existing gem callback will overwrite the previous callback.
          def on_require(gem, &block)
            # Defensive check, should not happen, as Pacher#patch should have been called before.
            if Patch.class_variable_defined?(:@@dd_instance)
              Patch.class_variable_get(:@@dd_instance).on_require(gem, &block)
            end
          end

          # Remove the callback for when a gem is required for gems that we've already patched.
          def delete_on_require(gem)
            # Defensive check, should not happen, as Pacher#patch should have been called before.
            if Patch.class_variable_defined?(:@@dd_instance)
              Patch.class_variable_get(:@@dd_instance).delete_on_require(gem)
            end
          end

          # private
          #
          # # Only use this method for resetting patching in between test runs.
          # def reset_patch!
          #   Patch.class_variable_set(:@@dd_instance, Instance.new) if Patch.class_variable_defined?(:@@dd_instance)
          # end
        end

        # Actual changes to the `Kernel` module.
        module Patch
          # Initialize the internal instance on patch.
          def self.prepended(base)
            @@dd_instance = Instance.new
          end

          # A patch to the global `require` that executes a callback
          # when a gem is required for the first time.
          def require(name)
            # Returns `true` if file was loaded by this `super` operation.
            # If it was already loaded, returns `false`.
            # If `super` errs, it will raise an exception.
            just_loaded = super

            @@dd_instance.require(name) if just_loaded

            just_loaded
          end
        end

        # Helper class to register callbacks for `Kernel#require`.
        # Having a separate class allows for easier testing.
        class Instance
          def initialize
            @on_require = {}
          end

          # Executes the callback for when a gem is loaded.
          def require(name)
            callback = @on_require[name]
            return unless callback

            Datadog.logger.debug { "Gem '#{name}' loaded. Invoking datadog callback." }

            callback.call
          rescue => e
            Datadog.logger.debug do
              "Datadog callback failed for gem '#{name}': #{e.class.name} #{e.message} at #{Array(e.backtrace).join("\n")}"
            end
          end

          # Registers a callback for when a gem is required.
          # Invoking it with an existing gem callback will overwrite the previous callback.
          def on_require(gem, &block)
            @on_require[gem] = block
          end

          # Remove the callback for when a gem is required.
          def delete_on_require(gem)
            @on_require.delete(gem)
          end
        end

        # Patcher helper to manage the only-once requirement.
        module Patcher
          include Contrib::Patcher

          def self.patch
            ::Kernel.prepend(Patch)
          end
        end
      end
    end
  end
end
