# frozen_string_literal: true

# Declarative WebMock enablement.
#
# `spec/spec_helper.rb` calls `WebMock.disable!` as the suite-level default so
# real HTTP connections pass through unless an example opts in. Examples that
# rely on `stub_request` must enable WebMock first or the stubs become no-ops.
#
# Usage:
#
#   RSpec.describe Foo, webmock: true do
#     before { stub_request(:post, '...').to_return(status: 200) }
#     # ...
#   end
#
# or per-context:
#
#   context 'when the agent responds 200', webmock: true do
#     before { stub_request(...).to_return(...) }
#   end
#
# Examples (or groups) that need extra options like `WebMock.enable!(allow: x)`
# should keep the imperative form.
RSpec.shared_context 'webmock' do
  before { WebMock.enable! }

  after do
    WebMock.reset!
    WebMock.disable!
  end
end

RSpec.configure do |config|
  config.include_context 'webmock', webmock: true
end
