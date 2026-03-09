# frozen_string_literal: true

require_relative 'symbol_database/configuration'
require_relative 'symbol_database/remote'

module Datadog
  # Namespace for Datadog symbol database upload.
  #
  # @api private
  module SymbolDatabase
    @mutex = Mutex.new
    @component = nil

    class << self
      def component
        @mutex.synchronize { @component }
      end

      def set_component(component)
        @mutex.synchronize { @component = component }
      end

      def enabled?
        !component.nil?
      end
    end
  end
end
