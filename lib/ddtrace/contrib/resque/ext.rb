module Datadog
  module Contrib
    module Resque
      # Resque integration constants
      module Ext
        APP = 'resque'.freeze
        SERVICE_NAME = 'resque'.freeze

        SPAN_JOB = 'resque.job'.freeze
      end
    end
  end
end
