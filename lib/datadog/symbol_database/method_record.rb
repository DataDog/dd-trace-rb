# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Resolved metadata for one instance method a class declares, produced by
    # Extractor in a single introspection pass so the class line range and the
    # METHOD scopes reuse one resolution per method.
    #
    # @api private
    class MethodRecord < Struct.new(
      :name,
      :source_file,
      :start_line,
      :end_line,
      :targetable_lines,
      :visibility,
      :arity,
      :parameters,
      :user_code,
      keyword_init: true
    )
    end
  end
end
