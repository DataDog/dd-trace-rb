# frozen_string_literal: true

require_relative 'symbol_database/configuration'
require_relative 'symbol_database/extensions'
require_relative 'symbol_database/remote'

module Datadog
  # Namespace for Datadog symbol database upload.
  #
  # @api private
  module SymbolDatabase
    class << self
      def enabled?
        Datadog.configuration.symbol_database.enabled
      end

      def component
        Datadog.send(:components).symbol_database
      end
    end
  end
end
