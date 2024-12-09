# frozen_string_literal: true

require_relative '../patcher'
require_relative 'patcher/authenticatable_patch'
require_relative 'patcher/rememberable_patch'
require_relative 'patcher/registration_controller_patch'

module Datadog
  module AppSec
    module Contrib
      module Devise
        # Patcher for AppSec on Devise
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            patch_authenticatable_strategy
            patch_rememberable_strategy
            patch_registration_controller

            Patcher.instance_variable_set(:@patched, true)
          end

          def patch_authenticatable_strategy
            ::Devise::Strategies::Authenticatable.prepend(AuthenticatablePatch)
          end

          def patch_rememberable_strategy
            return unless ::Devise::STRATEGIES.include?(:rememberable)

            # Rememberable strategy is required in autoloaded Rememberable model
            ::Devise::Models::Rememberable # rubocop:disable Lint/Void
            ::Devise::Strategies::Rememberable.prepend(RememberablePatch)
          end

          def patch_registration_controller
            ::ActiveSupport.on_load(:after_initialize) do
              ::Devise::RegistrationsController.prepend(RegistrationControllerPatch)
            end
          end
        end
      end
    end
  end
end
