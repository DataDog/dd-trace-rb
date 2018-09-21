module Datadog
  module Contrib
    module Rake
      # Rake integration constants
      module Ext
        APP = 'rake'.freeze
        SERVICE_NAME = 'rake'.freeze

        SPAN_INVOKE = 'rake.invoke'.freeze
        SPAN_EXECUTE = 'rake.execute'.freeze

        TAG_EXECUTE_ARGS = 'rake.execute.args'.freeze
        TAG_INVOKE_ARGS = 'rake.invoke.args'.freeze
        TAG_TASK_ARG_NAMES = 'rake.task.arg_names'.freeze
      end
    end
  end
end
