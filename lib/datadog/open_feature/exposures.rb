# frozen_string_literal: true

module Datadog
  module OpenFeature
    # This module contains the exposures events functionality
    module Exposures
    end
  end
end

require_relative 'exposures/buffer'
require_relative 'exposures/worker'
require_relative 'exposures/deduplicator'
require_relative 'exposures/reporter'
