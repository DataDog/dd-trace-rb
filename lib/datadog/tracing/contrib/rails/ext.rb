# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Rails
        # Rails integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          APP = 'rails'
          ENV_ENABLED = 'DD_TRACE_RAILS_ENABLED'
          # @!visibility private
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_RAILS_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RAILS_ANALYTICS_SAMPLE_RATE'
          ENV_DISABLE = 'DISABLE_DATADOG_RAILS'

          # @!visibility private
          MINIMUM_VERSION = Gem::Version.new('4')
        end
      end
    end
  end
end
