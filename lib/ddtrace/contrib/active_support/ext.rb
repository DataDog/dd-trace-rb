module Datadog
  module Contrib
    module ActiveSupport
      # ActiveSupport integration constants
      module Ext
        APP = 'active_support'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_ACTIVE_SUPPORT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_ACTIVE_SUPPORT_ANALYTICS_SAMPLE_RATE'.freeze
        QUANTIZE_CACHE_MAX_KEY_SIZE = 300
        RESOURCE_CACHE_DELETE = 'DELETE'.freeze
        RESOURCE_CACHE_GET = 'GET'.freeze
        RESOURCE_CACHE_SET = 'SET'.freeze
        SERVICE_CACHE = 'active_support-cache'.freeze
        SPAN_CACHE = 'rails.cache'.freeze
        SPAN_TYPE_CACHE = 'cache'.freeze
        TAG_CACHE_BACKEND = 'rails.cache.backend'.freeze
        TAG_CACHE_KEY = 'rails.cache.key'.freeze
      end
    end
  end
end
