# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Binding
      # Variation types supported by UFC (Universal Flag Configuration)
      module VariationType
        STRING = 'STRING'
        INTEGER = 'INTEGER'
        NUMERIC = 'NUMERIC'
        BOOLEAN = 'BOOLEAN'
        JSON = 'JSON'
      end
    end
  end
end