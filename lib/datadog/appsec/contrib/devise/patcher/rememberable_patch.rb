# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patcher
          # To avoid tracking new sessions that are created by
          # Rememberable strategy as Login Success events.
          module RememberablePatch
            def validate(*args)
              __validate_datadog_authenticatable(*args)
            end
          end
        end
      end
    end
  end
end
