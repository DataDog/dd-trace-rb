# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Gateway
          Request = Struct.new(:host, :user_agent, :remote_addr, :headers, keyword_init: true)
        end
      end
    end
  end
end
