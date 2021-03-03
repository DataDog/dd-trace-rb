RSpec.shared_context 'OpenTracing helpers' do
  before do
    skip 'OpenTracing not supported' unless Datadog::OpenTracer.supported?
  end
end
