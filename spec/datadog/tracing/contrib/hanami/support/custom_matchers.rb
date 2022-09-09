RSpec::Matchers.define :be_hanami_rack_span do
  match(notify_expectation_failures: true) do |span|
    expect(span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST)
    expect(span).to be_root_span
    expect(span.resource).to eq(@resource)

    expect(span.service).to eq(tracer.default_service)
    expect(span.span_type).to eq('web')
    expect(span.get_tag('http.method')).to eq(@http_method)
    expect(span.get_tag('http.status_code')).to eq(@http_status_code)
    if @error
      expect(span).to have_error
    else
      expect(span).to_not have_error
    end
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
  end

  chain :with do |opts|
    @resource = opts.fetch(:resource)
    @http_method = opts.fetch(:http_method, 'GET')
    @http_status_code = opts.fetch(:http_status_code, 200).to_s
    @error = opts.fetch(:have_error, false)
  end
end

RSpec::Matchers.define :be_hanami_routing_span do
  match(notify_expectation_failures: true) do |span|
    expect(span.name).to eq(Datadog::Tracing::Contrib::Hanami::Ext::SPAN_ROUTING)
    expect(span.parent_id).to eq(@parent.id)
    expect(span.resource).to eq(@resource)

    expect(span.span_type).to eq('web')
    expect(span.service).to eq(tracer.default_service)
    expect(span).to_not have_error
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('routing')
  end

  chain :with do |opts|
    @resource = opts.fetch(:resource)
    @parent = opts.fetch(:parent)
  end
end

RSpec::Matchers.define :be_hanami_action_span do
  match(notify_expectation_failures: true) do |span|
    expect(span.name).to eq(Datadog::Tracing::Contrib::Hanami::Ext::SPAN_ACTION)
    expect(span.parent_id).to eq(@parent.id)
    expect(span.resource).to eq(@resource)

    expect(span.span_type).to eq('web')
    expect(span.service).to eq(tracer.default_service)
    expect(span).to_not have_error
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('action')
  end

  chain :with do |opts|
    @resource = opts.fetch(:resource)
    @parent = opts.fetch(:parent)
  end
end

RSpec::Matchers.define :be_hanami_render_span do
  match(notify_expectation_failures: true) do |span|
    expect(span.name).to eq(Datadog::Tracing::Contrib::Hanami::Ext::SPAN_RENDER)
    expect(span.parent_id).to eq(@parent.id)
    expect(span.resource).to eq(@resource)

    expect(span.span_type).to eq('web')
    expect(span.service).to eq(tracer.default_service)
    expect(span).to_not have_error
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('render')
  end

  chain :with do |opts|
    @resource = opts.fetch(:resource)
    @parent = opts.fetch(:parent)
  end
end
