# frozen_string_literal: true

require 'spec_helper'
require 'datadog'

RSpec.describe 'Remote Configuration bootstrap in non-Rack workloads', :integration do
  before do
    WebMock.enable!
    stub_request(:get, %r{/info}).to_return(
      body: {endpoints: ['/info', '/v0.7/config']}.to_json,
      status: 200,
    )
    stub_request(:post, %r{/v0\.7/config}).to_return(body: '{}', status: 200)

    Datadog::Core::Remote::Tie.send(:reset_for_tests!)
  end

  after do
    Datadog.shutdown!
    WebMock.disable!
  end

  it 'starts the RC worker the first time a span is created' do
    Datadog.configure do |c|
      c.remote.enabled = true
      c.remote.poll_interval_seconds = 60 # don't hammer the stub
      c.remote.boot_timeout_seconds = 2
    end

    remote = Datadog.send(:components).remote
    expect(remote).not_to be_nil
    expect(remote.started?).to be false

    Datadog::Tracing.trace('sidekiq.process') { :noop }

    expect(remote.started?).to be true
  end

  it 'does not start the RC worker if no span is ever created' do
    Datadog.configure do |c|
      c.remote.enabled = true
      c.remote.poll_interval_seconds = 60
      c.remote.boot_timeout_seconds = 2
    end

    remote = Datadog.send(:components).remote
    expect(remote.started?).to be false

    # Don't create any spans. Worker should still be quiescent.
    expect(remote.started?).to be false
  end
end
