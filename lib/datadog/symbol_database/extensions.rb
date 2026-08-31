# frozen_string_literal: true

require_relative "../core/configuration"
require_relative "configuration"

module Datadog
  module SymbolDatabase
    # Registers the symbol_database settings group on core's Settings.
    module Extensions
      # Extends core Settings with the symbol_database settings group.
      # @return [void]
      def self.activate!
        Core::Configuration::Settings.extend(Configuration::Settings)
      end
    end
  end
end

Datadog::SymbolDatabase::Extensions.activate!
