# typed: ignore

RSpec.shared_examples_for 'propagated with sql comment propagation' do |mode, span_op_name|
  it "propagates with mode: #{mode}" do
    expect(Datadog::Tracing::Contrib::Propagation::SqlComment::Mode)
      .to receive(:new).with(mode).and_return(propagation_mode)

    subject
  end

  it 'decorates the span operation' do
    expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:annotate!).with(
      a_span_operation_with(name: span_op_name),
      propagation_mode
    )
    subject
  end

  it 'prepends sql comment to the sql statement' do
    expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:prepend_comment).with(
      sql_statement,
      a_span_operation_with(name: span_op_name, service: service_name),
      propagation_mode
    ).and_call_original

    subject
  end
end
