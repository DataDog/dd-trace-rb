# frozen_string_literal: true

require_relative 'core/dependency'

module Datadog
  module Core
    class << self
      # DEV: needs to be loaded before `ddtrace` module and classes are loaded to
      # DEV: support dependency declaration DSL.
      def dependency_registry
        @dependency_registry ||= Core::Dependency::Registry.new
      end
    end
  end
end
