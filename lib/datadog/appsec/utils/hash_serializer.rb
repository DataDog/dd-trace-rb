# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      # TODO: Write description
      module HashSerializer
        # NOTE: TODO Write about best effort
        module_function def to_hash(object)
          return object.as_json if object.respond_to?(:as_json)
          return object.to_hash if object.respond_to?(:to_hash)
          return object.to_h if object.respond_to?(:to_h)

          nil
        end
      end
    end
  end
end
