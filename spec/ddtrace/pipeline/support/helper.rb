# typed: true
require 'ddtrace/span'

module PipelineHelpers
  def generate_span(name, parent = nil)
    Datadog::Span.new(name, parent_id: parent ? parent.span_id : 0)
  end
end
