RSpec.shared_context 'OpenTracing helpers' do
  before(:each) do
    skip 'OpenTracing not supported' unless Datadog::OpenTracer.supported?
  end
end
