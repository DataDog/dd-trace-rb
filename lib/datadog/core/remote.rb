# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      class << self
        def active_remote
          remote
        end

        private

        def components
          Datadog.send(:components)
        end

        def remote
          components.remote
        end
      end
    end
  end
end
