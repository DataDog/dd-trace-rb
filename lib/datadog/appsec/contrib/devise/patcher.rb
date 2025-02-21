# frozen_string_literal: true

require_relative 'patches/signup_tracking_patch'
require_relative 'patches/signin_tracking_patch'
require_relative 'patches/skip_signin_tracking_patch'

module Datadog
  module AppSec
    module Contrib
      module Devise
        # Devise patcher
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
              ::Devise::RegistrationsController.prepend(Patches::SignupTrackingPatch)
            end

            ::Devise::Strategies::Authenticatable.prepend(Patches::SigninTrackingPatch)

            if ::Devise::STRATEGIES.include?(:rememberable)
              # Rememberable strategy is required in autoloaded Rememberable model
              require 'devise/models/rememberable'
              ::Devise::Strategies::Rememberable.prepend(Patches::SkipSigninTrackingPatch)
            end

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
