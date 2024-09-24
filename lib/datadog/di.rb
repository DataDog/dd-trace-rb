# frozen_string_literal: true

require_relative 'di/configuration'
require_relative 'di/extensions'

module Datadog
  # Namespace for Datadog dynamic instrumentation.
  #
  # @api private
  module DI
    # Expose DI to global shared objects
    Extensions.activate!
  end
end
