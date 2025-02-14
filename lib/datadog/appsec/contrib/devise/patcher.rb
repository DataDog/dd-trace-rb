# frozen_string_literal: true

require_relative 'patcher/signin_tracking_patch'
require_relative 'patcher/signup_tracking_patch'
require_relative 'patcher/rememberable_patch'

module Datadog
  module AppSec
    module Contrib
      module Devise
        # Patcher for AppSec on Devise
        module Patcher
          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            ::ActiveSupport.on_load(:after_initialize) do
              ::Devise::RegistrationsController.prepend(SignupTrackingPatch)
            end

            ::Devise::Strategies::Authenticatable.prepend(SigninTrackingPatch)

            if ::Devise::STRATEGIES.include?(:rememberable)
              # Rememberable strategy is required in autoloaded Rememberable model
              require 'devise/models/rememberable'
              ::Devise::Strategies::Rememberable.prepend(RememberablePatch)
            end

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
