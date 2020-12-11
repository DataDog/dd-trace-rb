require 'ddtrace/span'

module PipelineHelpers
  def generate_span(name, parent = nil)
    Datadog::Span.new(nil, name).tap do |span|
      span.parent = parent
    end
  end
end
