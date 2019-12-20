RSpec.shared_context 'an unfinished trace' do
  let(:unfinished_span_name) { 'unfinished_span' }
  let!(:unfinished_span) { tracer.trace(unfinished_span_name) }

  before do
    expect(Datadog::Diagnostics::Health.metrics).to receive(:error_unfinished_context)
      .with(1, tags: [
              "span_name:#{unfinished_span_name}",
              "event:#{event_name}"
            ])
  end
end
