module Datadog
  module Ext
    module Environment
      ENV_API_KEY = 'DD_API_KEY'.freeze
      ENV_ENVIRONMENT = 'DD_ENV'.freeze
      ENV_SERVICE = 'DD_SERVICE'.freeze
      ENV_SITE = 'DD_SITE'.freeze
      ENV_TAGS = 'DD_TAGS'.freeze
      ENV_VERSION = 'DD_VERSION'.freeze

      TAG_ENV = 'env'.freeze
      TAG_SERVICE = 'service'.freeze
      TAG_VERSION = 'version'.freeze
    end
  end
end
