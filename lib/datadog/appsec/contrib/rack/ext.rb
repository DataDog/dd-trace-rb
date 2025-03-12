# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Rack integration constants
        module Ext
          IDENTITY_COLLECTABLE_REQUEST_HEADERS = [
            'accept-encoding',
            'accept-language',
            'cf-connecting-ip',
            'cf-connecting-ipv6',
            'content-encoding',
            'content-language',
            'content-length',
            'fastly-client-ip',
            'forwarded',
            'forwarded-for',
            'host',
            'true-client-ip',
            'via',
            'x-client-ip',
            'x-cluster-client-ip',
            'x-forwarded',
            'x-forwarded-for',
            'x-real-ip'
          ].freeze
        end
      end
    end
  end
end
