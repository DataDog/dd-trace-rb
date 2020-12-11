require 'spec_helper'

require 'ddtrace'
require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/headers'
require 'ddtrace/span'

RSpec.describe Datadog::DistributedTracing::Headers::Headers do
  subject(:headers) do
    described_class.new(env)
  end
  let(:env) { {} }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#header' do
    context 'header not present' do
      it { expect(headers.header('request_id')).to be_nil }
    end

    context 'header value is nil' do
      let(:env) { { env_header('request_id') => nil } }
      it { expect(headers.header('request_id')).to be_nil }
    end

    context 'header value is empty string' do
      let(:env) { { env_header('request_id') => '' } }
      it { expect(headers.header('request_id')).to be_nil }
    end

    context 'header is set' do
      %w[
        request_id
        request-id
        REQUEST_ID
        REQUEST-ID
        Request-ID
      ].each do |header|
        context "fetched as #{header}" do
          let(:env) { { env_header('request_id') => 'rid' } }
          it { expect(headers.header(header)).to eq('rid') }
        end
      end
    end
  end

  describe '#id' do
    context 'header not present' do
      it { expect(headers.id('trace_id')).to be_nil }
    end

    context 'header value is' do
      [
        [nil, nil],
        ['0', nil],
        ['value', nil],
        ['867-5309', nil],
        ['ten', nil],
        ['', nil],
        [' ', nil],

        # Larger than we allow
        [(Datadog::Span::EXTERNAL_MAX_ID + 1).to_s, nil],

        # Negative number
        ['-100', -100 + (2**64)],

        # Allowed values
        [Datadog::Span::RUBY_MAX_ID.to_s, Datadog::Span::RUBY_MAX_ID],
        [Datadog::Span::EXTERNAL_MAX_ID.to_s, Datadog::Span::EXTERNAL_MAX_ID],
        ['1', 1],
        ['100', 100],
        ['1000', 1000]
      ].each do |value, expected|
        context value.inspect do
          let(:env) { { env_header('trace_id') => value } }
          it { expect(headers.id('trace_id')).to eq(expected) }
        end
      end

      # Base 16
      [
        # Larger than we allow
        # DEV: We truncate to 64-bit for base16
        [(Datadog::Span::EXTERNAL_MAX_ID + 1).to_s(16), 1],
        [Datadog::Span::EXTERNAL_MAX_ID.to_s(16), nil],

        [Datadog::Span::RUBY_MAX_ID.to_s(16), Datadog::Span::RUBY_MAX_ID],
        [(Datadog::Span::EXTERNAL_MAX_ID - 1).to_s(16), Datadog::Span::EXTERNAL_MAX_ID - 1],

        ['3e8', 1000],
        ['3E8', 1000]
      ].each do |value, expected|
        context value.inspect do
          let(:env) { { env_header('trace_id') => value } }
          it { expect(headers.id('trace_id', 16)).to eq(expected) }
        end
      end
    end
  end

  describe '#number' do
    context 'header not present' do
      it { expect(headers.number('trace_id')).to be_nil }
    end

    context 'header value is' do
      [
        [nil, nil],
        ['value', nil],
        ['867-5309', nil],
        ['ten', nil],
        ['', nil],
        [' ', nil],

        # Sampling priorities
        ['-1', -1],
        ['0', 0],
        ['1', 1],
        ['2', 2],

        # Allowed values
        [Datadog::Span::RUBY_MAX_ID.to_s, Datadog::Span::RUBY_MAX_ID],
        [(Datadog::Span::RUBY_MAX_ID + 1).to_s, Datadog::Span::RUBY_MAX_ID + 1],
        [Datadog::Span::EXTERNAL_MAX_ID.to_s, Datadog::Span::EXTERNAL_MAX_ID],
        [(Datadog::Span::EXTERNAL_MAX_ID + 1).to_s, Datadog::Span::EXTERNAL_MAX_ID + 1],
        ['-100', -100],
        ['100', 100],
        ['1000', 1000]
      ].each do |value, expected|
        context value.inspect do
          let(:env) { { env_header('trace_id') => value } }
          it { expect(headers.number('trace_id')).to eq(expected) }
        end
      end

      # Base 16
      [
        # Larger than we allow
        # DEV: We truncate to 64-bit for base16, so the
        [Datadog::Span::EXTERNAL_MAX_ID.to_s(16), 0],
        [(Datadog::Span::EXTERNAL_MAX_ID + 1).to_s(16), 1],

        [Datadog::Span::RUBY_MAX_ID.to_s(16), Datadog::Span::RUBY_MAX_ID],
        [(Datadog::Span::RUBY_MAX_ID + 1).to_s(16), Datadog::Span::RUBY_MAX_ID + 1],

        ['3e8', 1000],
        ['3E8', 1000],
        ['deadbeef', 3735928559],
        ['10000', 65536],

        ['invalid-base16', nil]
      ].each do |value, expected|
        context value.inspect do
          let(:env) { { env_header('trace_id') => value } }
          it { expect(headers.number('trace_id', 16)).to eq(expected) }
        end
      end
    end
  end
end
