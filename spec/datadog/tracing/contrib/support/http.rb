RSpec.shared_context 'with trace header tags' do
  around do |example|
    ClimateControl.modify('DD_TRACE_HEADER_TAGS' => trace_header_tags_config) do
      example.run
    end
  end

  let(:header_span) { defined?(super) ? super() : span }
  let(:trace_header_tags_config) { nil }
end

RSpec.shared_examples 'with request tracer header tags' do
  context 'with request tracer header tags' do
    include_context 'with trace header tags'

    let(:request_header_tag) { defined?(super) ? super() : 'request-header-tag' }
    let(:request_header_tag_value) { defined?(super) ? super() : 'request-header-tag-value' }
    let(:trace_header_tags_config) { "#{request_header_tag}:#{request_header_tag}" }

    it 'sets the request header value as a tag' do
      expect(header_span.get_tag(request_header_tag)).to match(request_header_tag_value)
    end
  end
end

RSpec.shared_examples 'with response tracer header tags' do
  context 'with response tracer header tags' do
    include_context 'with trace header tags'

    let(:response_header_tag) { defined?(super) ? super() : 'response-header-tag' }
    let(:response_header_tag_value) { defined?(super) ? super() : 'response-header-tag-value' }
    let(:trace_header_tags_config) { "#{response_header_tag}:#{response_header_tag}" }

    it 'sets the response header value as a tag' do
      expect(header_span.get_tag(response_header_tag)).to match(response_header_tag_value)
    end
  end
end
