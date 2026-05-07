# frozen_string_literal: true

require 'datadog/core'

RSpec.describe 'Datadog::Tracing::Transport::Native::Response' do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:response_class) { native_module::Response }

  # Response objects are created by the C extension (create_ok_response /
  # create_error_response) and not directly by Ruby code.  To test the
  # reader methods we allocate an instance and set ivars manually, which
  # mirrors what the C helpers do.

  def make_response(ok:, internal_error: false, server_error: false,
                    client_error: false, not_found: false,
                    unsupported: false, trace_count: 0, payload: nil)
    resp = response_class.allocate
    resp.instance_variable_set(:@ok,             ok)
    resp.instance_variable_set(:@internal_error,  internal_error)
    resp.instance_variable_set(:@server_error,    server_error)
    resp.instance_variable_set(:@client_error,    client_error)
    resp.instance_variable_set(:@not_found,       not_found)
    resp.instance_variable_set(:@unsupported,     unsupported)
    resp.instance_variable_set(:@trace_count,     trace_count)
    resp.instance_variable_set(:@payload,         payload)
    resp
  end

  describe 'ok response' do
    subject(:response) { make_response(ok: true, trace_count: 5, payload: '{"rate_by_service":{}}') }

    it { expect(response.ok?).to be true }
    it { expect(response.internal_error?).to be false }
    it { expect(response.server_error?).to be false }
    it { expect(response.client_error?).to be false }
    it { expect(response.not_found?).to be false }
    it { expect(response.unsupported?).to be false }
    it { expect(response.trace_count).to eq(5) }
    it { expect(response.payload).to eq('{"rate_by_service":{}}') }
  end

  describe 'internal error response' do
    subject(:response) { make_response(ok: false, internal_error: true) }

    it { expect(response.ok?).to be false }
    it { expect(response.internal_error?).to be true }
    it { expect(response.server_error?).to be false }
    it { expect(response.client_error?).to be false }
    it { expect(response.payload).to be_nil }
  end

  describe 'server error response' do
    subject(:response) { make_response(ok: false, server_error: true) }

    it { expect(response.ok?).to be false }
    it { expect(response.internal_error?).to be false }
    it { expect(response.server_error?).to be true }
    it { expect(response.client_error?).to be false }
  end

  describe 'client error response' do
    subject(:response) { make_response(ok: false, client_error: true) }

    it { expect(response.ok?).to be false }
    it { expect(response.internal_error?).to be false }
    it { expect(response.server_error?).to be false }
    it { expect(response.client_error?).to be true }
  end

  describe 'nil payload' do
    subject(:response) { make_response(ok: true) }

    it { expect(response.payload).to be_nil }
  end
end
