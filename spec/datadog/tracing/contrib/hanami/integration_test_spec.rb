
require_relative './support/hanami_helpers'
require 'rack'
require 'rack/test'
require 'ddtrace'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/rack/ext'
require 'datadog/tracing/contrib/hanami/ext'

RSpec.describe 'Hanami instrumentation' do
  include Rack::Test::Methods
  include_context 'Hanami test application'

  let(:rack_span) { spans.find {|s| s.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST}}
  let(:routing_span) { spans.find {|s| s.name == Datadog::Tracing::Contrib::Hanami::Ext::SPAN_ROUTING}}
  let(:action_span) { spans.find {|s| s.name == Datadog::Tracing::Contrib::Hanami::Ext::SPAN_ACTION}}
  let(:render_span) { spans.find {|s| s.name == Datadog::Tracing::Contrib::Hanami::Ext::SPAN_RENDER}}

  context do
    subject(:response) { get 'simple_success' }

    it do
      subject

      expect(response.status).to eq(200)

      expect(spans).to have(3).items

      expect(rack_span).to be_root_span
      expect(rack_span.span_type).to eq('web')
      expect(rack_span.service).to eq(tracer.default_service)
      expect(rack_span.resource).to eq('GET 200')
      expect(rack_span.get_tag('http.method')).to eq('GET')
      expect(rack_span.get_tag('http.status_code')).to eq('200')
      expect(rack_span.status).to eq(0)
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')

      expect(routing_span.parent_id).to eq(rack_span.id)
      expect(routing_span.span_type).to eq('web')
      expect(routing_span.service).to eq(tracer.default_service)
      expect(routing_span.resource).to eq('GET')
      expect(routing_span.status).to eq(0)
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('routing')

      expect(render_span.parent_id).to eq(routing_span.id)
      expect(render_span.span_type).to eq('web')
      expect(render_span.service).to eq(tracer.default_service)
      expect(render_span.resource).to eq('NilClass')
      expect(render_span.status).to eq(0)
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('render')
    end
  end

  context do
    subject(:response) { get 'books' }

    it do
      subject

      expect(response.status).to eq(200)

      expect(spans).to have(4).items

      expect(rack_span).to be_root_span
      expect(rack_span.span_type).to eq('web')
      expect(rack_span.service).to eq(tracer.default_service)
      expect(rack_span.resource).to eq('Dummy::Controllers::Books::Index')
      expect(rack_span.get_tag('http.method')).to eq('GET')
      expect(rack_span.get_tag('http.status_code')).to eq('200')
      expect(rack_span.status).to eq(0)
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')

      expect(routing_span.parent_id).to eq(rack_span.id)
      expect(routing_span.span_type).to eq('web')
      expect(routing_span.service).to eq(tracer.default_service)
      expect(routing_span.resource).to eq('Dummy::Controllers::Books::Index')
      expect(routing_span.status).to eq(0)
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('routing')

      expect(action_span.parent_id).to eq(routing_span.id)
      expect(action_span.span_type).to eq('web')
      expect(action_span.service).to eq(tracer.default_service)
      expect(action_span.resource).to eq('Dummy::Controllers::Books::Index')
      expect(action_span.status).to eq(0)
      expect(action_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(action_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('action')

      expect(render_span.parent_id).to eq(routing_span.id)
      expect(render_span.span_type).to eq('web')
      expect(render_span.service).to eq(tracer.default_service)
      expect(render_span.resource).to eq('Dummy::Controllers::Books::Index')
      expect(render_span.status).to eq(0)
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('render')
    end
  end


  context do
    subject(:response) { get 'not_found' }

    it do
      subject

      expect(response.status).to eq(404)

      expect(spans).to have(3).items

      expect(rack_span).to be_root_span
      expect(rack_span.span_type).to eq('web')
      expect(rack_span.service).to eq(tracer.default_service)
      expect(rack_span.resource).to eq('GET 404')
      expect(rack_span.get_tag('http.method')).to eq('GET')
      expect(rack_span.get_tag('http.status_code')).to eq('404')
      expect(rack_span.status).to eq(0)
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')

      expect(routing_span.parent_id).to eq(rack_span.id)
      expect(routing_span.span_type).to eq('web')
      expect(routing_span.service).to eq(tracer.default_service)
      expect(routing_span.resource).to eq('GET')
      expect(routing_span.status).to eq(0)
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('routing')

      expect(render_span.parent_id).to eq(routing_span.id)
      expect(render_span.span_type).to eq('web')
      expect(render_span.service).to eq(tracer.default_service)
      expect(render_span.resource).to eq('Hanami::Routing::Default::NullAction')
      expect(render_span.status).to eq(0)
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('render')
    end
  end

  context do
    subject(:response) { get 'server_error' }

    it do
      subject

      expect(response.status).to eq(500)

      expect(spans).to have(4).items

      expect(rack_span).to be_root_span
      expect(rack_span.span_type).to eq('web')
      expect(rack_span.service).to eq(tracer.default_service)
      expect(rack_span.resource).to eq('Dummy::Controllers::Books::ServerError')
      expect(rack_span.get_tag('http.method')).to eq('GET')
      expect(rack_span.get_tag('http.status_code')).to eq('500')
      expect(rack_span.status).to eq(1)
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
      expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')

      expect(routing_span.parent_id).to eq(rack_span.id)
      expect(routing_span.span_type).to eq('web')
      expect(routing_span.service).to eq(tracer.default_service)
      expect(routing_span.resource).to eq('Dummy::Controllers::Books::ServerError')
      expect(routing_span.status).to eq(0)
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(routing_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('routing')

      expect(action_span.parent_id).to eq(routing_span.id)
      expect(action_span.span_type).to eq('web')
      expect(action_span.service).to eq(tracer.default_service)
      expect(action_span.resource).to eq('Dummy::Controllers::Books::ServerError')
      expect(action_span.status).to eq(0)
      expect(action_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(action_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('action')

      expect(render_span.parent_id).to eq(routing_span.id)
      expect(render_span.span_type).to eq('web')
      expect(render_span.service).to eq(tracer.default_service)
      expect(render_span.resource).to eq('Dummy::Controllers::Books::ServerError')
      expect(render_span.status).to eq(0)
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('hanami')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('render')
    end
  end
end
