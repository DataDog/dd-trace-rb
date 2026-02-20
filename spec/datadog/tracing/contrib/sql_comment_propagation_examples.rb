RSpec.shared_examples_for 'with sql comment propagation' do |span_op_name:, error: nil|
  context 'when default `disabled`' do
    it_behaves_like 'propagates with sql comment', mode: 'disabled', span_op_name: span_op_name, error: error do
      let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new('disabled', append_comment, inject_sql_basehash) }
    end
  end

  context 'when ENV variable `DD_DBM_PROPAGATION_MODE` is provided' do
    with_env 'DD_DBM_PROPAGATION_MODE' => 'service'

    it_behaves_like 'propagates with sql comment', mode: 'service', span_op_name: span_op_name, error: error do
      let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new('service', append_comment, inject_sql_basehash) }
    end
  end

  %w[disabled service full].each do |mode|
    context "when `comment_propagation` is configured to #{mode}" do
      let(:configuration_options) do
        {comment_propagation: mode, service_name: service_name}
      end

      it_behaves_like 'propagates with sql comment', mode: mode, span_op_name: span_op_name, error: error do
        let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new(mode, append_comment, inject_sql_basehash) }
      end
    end
  end

  context 'when `inject_sql_basehash` is configured' do
    let(:configuration_options) do
      {comment_propagation: 'service', inject_sql_basehash: true, service_name: service_name}
    end

    let(:inject_sql_basehash) { true }

    it_behaves_like 'propagates with sql comment', mode: 'service', span_op_name: span_op_name, error: error do
      let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new('service', append_comment, inject_sql_basehash) }
    end
  end

  context 'when ENV variable `DD_DBM_INJECT_SQL_BASEHASH` is provided' do
    around do |example|
      ClimateControl.modify(
        'DD_DBM_PROPAGATION_MODE' => 'service',
        'DD_DBM_INJECT_SQL_BASEHASH' => 'true',
        &example
      )
    end

    let(:inject_sql_basehash) { true }

    it_behaves_like 'propagates with sql comment', mode: 'service', span_op_name: span_op_name, error: error do
      let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new('service', append_comment, inject_sql_basehash) }
    end
  end
end

RSpec.shared_examples_for 'propagates with sql comment' do |mode:, span_op_name:, error: nil|
  # super() is needed so the parent context can override the defaults for the new sql base hash tests.
  let(:append_comment) { defined?(super()) ? super() : false }
  let(:inject_sql_basehash) { defined?(super()) ? super() : false }

  it "propagates with mode: #{mode}" do
    expect(Datadog::Tracing::Contrib::Propagation::SqlComment::Mode)
      .to receive(:new).with(mode, append_comment, inject_sql_basehash).and_return(propagation_mode)

    if error
      expect { subject }.to raise_error(error)
    else
      subject
    end
  end

  it 'decorates the span operation' do
    expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:annotate!).with(
      a_span_operation_with(name: span_op_name),
      propagation_mode
    )
    if error
      expect { subject }.to raise_error(error)
    else
      subject
    end
  end

  it 'prepends sql comment to the sql statement' do
    allow(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:prepend_comment).and_call_original

    if error
      expect { subject }.to raise_error(error)
    else
      subject
    end

    expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to have_received(:prepend_comment).with(
      sql_statement,
      a_span_operation_with(service: service_name),
      duck_type(:to_digest),
      propagation_mode
    )
  end

  context 'in append mode' do
    let(:append_comment) { true }
    let(:configuration_options) { super().merge(append_comment: append_comment) }

    it 'appends sql comment to the sql statement' do
      allow(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:prepend_comment).and_call_original

      if error
        expect { subject }.to raise_error(error)
      else
        subject
      end

      expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to have_received(:prepend_comment).with(
        sql_statement,
        a_span_operation_with(service: service_name),
        duck_type(:to_digest),
        propagation_mode
      )
    end
  end
end

RSpec.shared_examples_for 'with sql comment base hash injection' do |span_op_name:|
  let(:agent_info) { instance_double(Datadog::Core::Environment::AgentInfo, propagation_checksum: 1234567890, fetch: nil) }
  let(:profiler) { double(enabled?: false) }

  before do
    allow(Datadog).to receive(:send).with(:components).and_return(double(agent_info: agent_info, tracer: tracer, profiler: profiler))
  end

  context 'when inject_sql_basehash is enabled and experimental_propagate_process_tags_enabled is true' do
    before do
      Datadog.configure do |c|
        c.experimental_propagate_process_tags_enabled = true
      end
    end

    after do
      without_warnings { Datadog.configuration.reset! }
    end

    let(:configuration_options) do
      {comment_propagation: 'service', inject_sql_basehash: true, service_name: service_name}
    end

    it 'injects base hash in the _dd.propagated_hash span tag' do
      subject

      span = spans.find { |s| s.name == span_op_name }
      expect(span).not_to be_nil
      expect(span.get_tag('_dd.propagated_hash')).to eq('1234567890')
    end
  end

  context 'when inject_sql_basehash is enabled but experimental_propagate_process_tags_enabled is false' do
    around do |example|
      without_warnings { Datadog.configuration.reset! }
      Datadog.configure do |c|
        c.experimental_propagate_process_tags_enabled = false
      end
      example.run
      without_warnings { Datadog.configuration.reset! }
    end

    let(:configuration_options) do
      {comment_propagation: 'service', inject_sql_basehash: true, service_name: service_name}
    end

    it 'does not inject base hash span tag' do
      subject

      span = spans.find { |s| s.name == span_op_name }
      expect(span).not_to be_nil
      expect(span.get_tag('_dd.propagated_hash')).to be_nil
    end
  end

  context 'when inject_sql_basehash is disabled but experimental_propagate_process_tags_enabled is true' do
    around do |example|
      without_warnings { Datadog.configuration.reset! }
      Datadog.configure do |c|
        c.experimental_propagate_process_tags_enabled = true
      end
      example.run
      without_warnings { Datadog.configuration.reset! }
    end

    let(:configuration_options) do
      {comment_propagation: 'service', inject_sql_basehash: false, service_name: service_name}
    end

    it 'does not inject base hash in the _dd.propagated_hash span tag' do
      subject

      span = spans.find { |s| s.name == span_op_name }
      expect(span).not_to be_nil
      expect(span.get_tag('_dd.propagated_hash')).to be_nil
    end
  end
end
