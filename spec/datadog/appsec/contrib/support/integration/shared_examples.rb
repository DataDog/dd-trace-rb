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
    expect(service_span.send(:meta)['_dd.appsec.triggers']).to be_nil
  end
end

RSpec.shared_examples 'a trace with AppSec events' do |params = { blocking: false }|
  let(:blocking_request) { params[:blocking] }

  it do
    expect(spans.select { |s| s.get_tag('appsec.event') }).to_not be_empty
    expect(service_span.send(:meta)['_dd.appsec.json']).to be_a String
    expect(spans.select { |s| s.get_tag('appsec.blocked') }).to_not be_empty if blocking_request
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }

    it_behaves_like 'a trace without AppSec events'
  end
end

RSpec.shared_examples 'a trace with ASM Standalone tags' do
  context 'with appsec enabled' do
    let(:appsec_enabled) { true }
    it do
      expect(service_span.send(:metrics)['_dd.apm.enabled']).to eq(0)
      expect(service_span.send(:metrics)['_dd.appsec.enabled']).to eq(1.0)
      expect(service_span.send(:meta)['_dd.runtime_family']).to eq('ruby')
      expect(service_span.send(:meta)['_dd.appsec.waf.version']).to match(/^\d+\.\d+\.\d+/)
    end
  end

  context 'with appsec disabled' do
    let(:appsec_enabled) { false }
    it do
      expect(service_span.send(:metrics)['_dd.apm.enabled']).to be_nil
      expect(service_span.send(:metrics)['_dd.appsec.enabled']).to be_nil
      expect(service_span.send(:meta)['_dd.runtime_family']).to be_nil
      expect(service_span.send(:meta)['_dd.appsec.waf.version']).to be_nil
    end
  end
end
