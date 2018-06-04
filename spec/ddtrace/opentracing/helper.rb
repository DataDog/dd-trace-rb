RSpec.shared_context 'OpenTracing helpers' do
  before(:each) do
    skip 'OpenTracing not supported' unless Datadog::OpenTracing.supported?
  end
end
