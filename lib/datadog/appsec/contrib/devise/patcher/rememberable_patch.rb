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
              @_datadog_skip_track_login_event = true

              super
            end
          end
        end
      end
    end
  end
end
