# frozen_string_literal: true

require_relative 'configuration/settings'

module Datadog
  module SymbolDatabase
    # Extends Datadog configuration with symbol_database settings
    module Extensions
      def self.extended(base)
        base.class_eval do
          SymbolDatabase::Configuration::Settings.add_settings!(self)
        end
      end
    end
  end
end

# Extend the settings class
Datadog::Core::Configuration::Settings.extend(Datadog::SymbolDatabase::Extensions)
