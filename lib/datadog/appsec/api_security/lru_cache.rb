# frozen_string_literal: true

require 'datadog/core/utils/lru_cache'

module Datadog
  module AppSec
    module APISecurity
      LRUCache = Datadog::Core::Utils::LRUCache
    end
  end
end
