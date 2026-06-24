# frozen_string_literal: true

require_relative '../core/configuration'
require_relative 'configuration'

module Datadog
  module SymbolDatabase
    # Registers the symbol_database settings group on core's Settings.
    #
    # This is deliberately not required by datadog/core: the
    # symbol_database.enabled default reads dynamic_instrumentation.enabled,
    # which only exists once DI's settings are registered. Activating here,
    # on the full-library load path alongside DI (see datadog/di.rb), keeps
    # the invariant that symbol_database settings exist only when
    # dynamic_instrumentation settings do — so the default never dereferences
    # a missing DI settings group.
    module Extensions
      def self.activate!
        Core::Configuration::Settings.extend(Configuration::Settings)
      end
    end
  end
end
