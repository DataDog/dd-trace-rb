# typed: true
module Datadog
  module Ext
    # @public_api
    module NET
      ENV_REPORT_HOSTNAME = 'DD_TRACE_REPORT_HOSTNAME'.freeze
      TAG_HOSTNAME = '_dd.hostname'.freeze
      TARGET_HOST = 'out.host'.freeze
      TARGET_PORT = 'out.port'.freeze
    end
  end
end
