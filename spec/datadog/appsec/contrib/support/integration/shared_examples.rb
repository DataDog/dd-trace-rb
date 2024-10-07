RSpec.shared_examples 'normal with tracing disable' do
  let(:tracing_enabled) { false }

  it do
    expect(spans).to have(0).items
  end
end

RSpec.shared_examples 'a GET 200 span' do
  it do
    expect(span.get_tag('http.method')).to eq('GET')
    expect(span.get_tag('http.status_code')).to eq('200')
    expect(span.status).to eq(0)
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it do
      expect(span.get_tag('http.method')).to eq('GET')
      expect(span.get_tag('http.status_code')).to eq('200')
      expect(span.status).to eq(0)
    end
  end
end

RSpec.shared_examples 'a GET 403 span' do
  it do
    expect(span.get_tag('http.method')).to eq('GET')
    expect(span.get_tag('http.status_code')).to eq('403')
    expect(span.status).to eq(0)
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it do
      expect(span.get_tag('http.method')).to eq('GET')
      expect(span.get_tag('http.status_code')).to eq('200')
      expect(span.status).to eq(0)
    end
  end
end

RSpec.shared_examples 'a GET 404 span' do
  it do
    expect(span.get_tag('http.method')).to eq('GET')
    expect(span.get_tag('http.status_code')).to eq('404')
    expect(span.status).to eq(0)
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it do
      expect(span.get_tag('http.method')).to eq('GET')
      expect(span.get_tag('http.status_code')).to eq('404')
      expect(span.status).to eq(0)
    end
  end
end

RSpec.shared_examples 'a POST 200 span' do
  it do
    expect(span.get_tag('http.method')).to eq('POST')
    expect(span.get_tag('http.status_code')).to eq('200')
    expect(span.status).to eq(0)
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it do
      expect(span.get_tag('http.method')).to eq('POST')
      expect(span.get_tag('http.status_code')).to eq('200')
      expect(span.status).to eq(0)
    end
  end
end

RSpec.shared_examples 'a POST 403 span' do
  it do
    expect(span.get_tag('http.method')).to eq('POST')
    expect(span.get_tag('http.status_code')).to eq('403')
    expect(span.status).to eq(0)
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it do
      expect(span.get_tag('http.method')).to eq('POST')
      expect(span.get_tag('http.status_code')).to eq('200')
      expect(span.status).to eq(0)
    end
  end
end

RSpec.shared_examples 'a trace without AppSec tags' do
  it do
    expect(service_span.send(:metrics)['_dd.appsec.enabled']).to be_nil
    expect(service_span.send(:meta)['_dd.runtime_family']).to be_nil
    expect(service_span.send(:meta)['_dd.appsec.waf.version']).to be_nil
    expect(span.send(:meta)['http.client_ip']).to eq nil
  end
end

RSpec.shared_examples 'a trace with AppSec tags' do
  it do
    expect(service_span.send(:metrics)['_dd.appsec.enabled']).to eq(1.0)
    expect(service_span.send(:meta)['_dd.runtime_family']).to eq('ruby')
    expect(service_span.send(:meta)['_dd.appsec.waf.version']).to match(/^\d+\.\d+\.\d+/)
    expect(span.send(:meta)['http.client_ip']).to eq client_ip
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it_behaves_like 'a trace without AppSec tags'
  end
end

RSpec.shared_examples 'a trace with AppSec api security tags' do
  context 'with api security enabled' do
    let(:api_security_enabled) { true }
    let(:api_security_sample) { 1.0 }

    it do
      api_security_tags = service_span.send(:meta).select { |key, _value| key.include?('_dd.appsec.s') }

      expect(api_security_tags).to_not be_empty
    end
  end

  context 'with api security disabled' do
    let(:api_security_enabled) { false }

    it do
      api_security_tags = service_span.send(:meta).select { |key, _value| key.include?('_dd.appsec.s') }

      expect(api_security_tags).to be_empty
    end
  end
end

RSpec.shared_examples 'a trace without AppSec events' do
  it do
    expect(spans.select { |s| s.get_tag('appsec.event') }).to be_empty
    expect(trace.send(:meta)['_dd.p.appsec']).to be_nil
    expect(service_span.send(:meta)['_dd.appsec.triggers']).to be_nil
  end
end

RSpec.shared_examples 'a trace with AppSec events' do |params = { blocking: false }|
  let(:blocking_request) { params[:blocking] }

  it do
    expect(spans.select { |s| s.get_tag('appsec.event') }).to_not be_empty
    expect(trace.send(:meta)['_dd.p.appsec']).to eq('1')
    expect(service_span.send(:meta)['_dd.appsec.json']).to be_a String
    expect(spans.select { |s| s.get_tag('appsec.blocked') }).to_not be_empty if blocking_request
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it_behaves_like 'a trace without AppSec events'
  end
end

RSpec.shared_examples 'a trace with ASM Standalone tags' do |params = {}|
  let(:tag_apm_enabled) { params[:tag_apm_enabled] || 0 }
  let(:tag_appsec_enabled) { params[:tag_appsec_enabled] || 1.0 }
  let(:tag_appsec_propagation) { params[:tag_appsec_propagation] }
  let(:tag_other_propagation) { params[:tag_other_propagation] || :any }
  # We use a lambda as we may change the comparison type
  let(:tag_sampling_priority_condition) { params[:tag_sampling_priority_condition] || ->(x) { x == 0 } }
  let(:tag_trace_id) { params[:tag_trace_id] || headers_trace_id.to_i }

  it do
    expect(span.send(:metrics)['_dd.apm.enabled']).to eq(tag_apm_enabled)
    expect(span.send(:metrics)['_dd.appsec.enabled']).to eq(tag_appsec_enabled)
    expect(span.send(:metrics)['_sampling_priority_v1']).to(satisfy { |x| tag_sampling_priority_condition.call(x) })

    expect(span.send(:meta)['_dd.p.appsec']).to eq(tag_appsec_propagation)
    expect(span.send(:meta)['_dd.p.other']).to eq(tag_other_propagation) unless tag_other_propagation == :any

    expect(span.send(:trace_id)).to eq(tag_trace_id)
    expect(trace.send(:spans)[0].send(:trace_id)).to eq(tag_trace_id)
  end
end

RSpec.shared_examples 'a request with propagated headers' do |params = {}|
  let(:res_origin) { params[:res_origin] }
  let(:res_parent_id_not_equal) { params[:res_parent_id_not_equal] }
  let(:res_tags) { params[:res_tags] }
  let(:res_sampling_priority_condition) { params[:res_sampling_priority_condition] || ->(x) { x.nil? } }
  let(:res_trace_id) { params[:res_trace_id] }

  let(:res_headers) { JSON.parse(response.body) }

  it do
    expect(res_headers['X-Datadog-Origin']).to eq(res_origin)
    expect(res_headers['X-Datadog-Parent']).to_not eq(res_parent_id_not_equal) if res_parent_id_not_equal
    expect(res_headers['X-Datadog-Sampling-Priority']).to(satisfy { |x| res_sampling_priority_condition.call(x) })
    expect(res_headers['X-Datadog-Trace-Id']).to eq(res_trace_id)
    expect(res_headers['X-Datadog-Tags'].split(',')).to include(*res_tags) if res_tags
  end
end

RSpec.shared_examples 'a trace sent to agent with Datadog-Client-Computed-Stats header' do
  let(:agent_tested_headers) { { 'Datadog-Client-Computed-Stats' => 'yes' } }

  it do
    agent_return = agent_http_client.send_traces(traces)
    expect(agent_return[0].ok?).to be true
  end
end

RSpec.shared_examples 'appsec standalone billing' do
  subject(:response) { get url, params, env }

  let(:appsec_standalone_enabled) { true }

  let(:url) { '/requestdownstream' }
  let(:params) { {} }
  let(:headers) do
    {
      'HTTP_X_DATADOG_TRACE_ID' => headers_trace_id,
      'HTTP_X_DATADOG_PARENT_ID' => headers_parent_id,
      'HTTP_X_DATADOG_SAMPLING_PRIORITY' => headers_sampling_priority,
      'HTTP_X_DATADOG_ORIGIN' => headers_origin,
      'HTTP_X_DATADOG_TAGS' => headers_tags,
      'HTTP_USER_AGENT' => user_agent
    }
  end
  let(:env) { headers }

  # Default values for headers
  let(:headers_trace_id) { '1212121212121212121' }
  let(:headers_parent_id) { '34343434' }
  let(:headers_origin) { 'rum' }
  let(:headers_sampling_priority) { '-1' }
  let(:headers_tags) { '_dd.p.other=1' }
  let(:user_agent) { nil }

  context 'without appsec upstream without attack and trace is kept with priority 1' do
    context 'from -1 sampling priority' do
      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_other_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x < 2 }
        }
      it_behaves_like 'a request with propagated headers'
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 0 sampling priority' do
      let(:headers_sampling_priority) { '0' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_other_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x < 2 }
        }
      it_behaves_like 'a request with propagated headers'
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 1 sampling priority' do
      let(:headers_sampling_priority) { '1' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_other_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x < 2 }
        }
      it_behaves_like 'a request with propagated headers'
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 2 sampling priority' do
      let(:headers_sampling_priority) { '2' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_other_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x < 2 }
        }
      it_behaves_like 'a request with propagated headers'
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end
  end

  context 'without upstream appsec propagation with attack and trace is kept with priority 2' do
    let(:user_agent) { 'Arachni/v1' }

    context 'from -1 sampling priority' do
      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x == 2 }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.other=1', '_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { x == '2' },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 0 sampling priority' do
      let(:headers_sampling_priority) { '0' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x == 2 }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.other=1', '_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { x == '2' },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end
  end

  context 'with upstream appsec propagation without attack and trace is propagated as is' do
    let(:headers_tags) { '_dd.p.appsec=1' }

    context 'from 0 sampling priority' do
      let(:headers_sampling_priority) { '0' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { [0, 2].include?(x) }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { ['0', '2'].include?(x) },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 1 sampling priority' do
      let(:headers_sampling_priority) { '1' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { [1, 2].include?(x) }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { ['1', '2'].include?(x) },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 2 sampling priority' do
      let(:headers_sampling_priority) { '2' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x == 2 }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { x == '2' },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end
  end

  context 'with any upstream propagation with attack and raises trace priority to 2' do
    let(:user_agent) { 'Arachni/v1' }
    let(:headers_tags) { nil }

    context 'from -1 sampling priority' do
      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x == 2 }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { x == '2' },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 0 sampling priority' do
      let(:headers_sampling_priority) { '0' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x == 2 }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { x == '2' },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end

    context 'from 1 sampling priority' do
      let(:headers_sampling_priority) { '1' }

      it_behaves_like 'a trace with ASM Standalone tags',
        {
          tag_appsec_propagation: '1',
          tag_sampling_priority_condition: ->(x) { x == 2 }
        }
      it_behaves_like 'a request with propagated headers',
        {
          res_origin: 'rum',
          res_parent_id_not_equal: '34343434',
          res_tags: ['_dd.p.appsec=1'],
          res_sampling_priority_condition: ->(x) { x == '2' },
          res_trace_id: '1212121212121212121'
        }
      it_behaves_like 'a trace sent to agent with Datadog-Client-Computed-Stats header'
    end
  end
end
