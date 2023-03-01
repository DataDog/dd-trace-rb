require 'datadog/tracing/span'

module PipelineHelpers
  def generate_span(name, parent = nil)
    Datadog::Tracing::Span.new(name, parent_id: parent ? parent.span_id : 0)
  end
end
