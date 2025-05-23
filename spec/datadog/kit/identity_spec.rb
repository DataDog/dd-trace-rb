require 'spec_helper'

require 'time'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/identity'

require 'datadog/appsec/context'

RSpec.describe Datadog::Kit::Identity do
  subject(:trace_op) { Datadog::Tracing::TraceOperation.new }

  describe '#set_user' do
    it 'sets user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42')
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'sets user email on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', email: 'foo@example.com')
        expect(span.tags).to include('usr.id' => '42', 'usr.email' => 'foo@example.com')
      end
    end

    it 'sets user name on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', name: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'usr.name' => 'bar')
      end
    end

    it 'sets user session id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', session_id: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'usr.session_id' => 'bar')
      end
    end

    it 'sets user role on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', role: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'usr.role' => 'bar')
      end
    end

    it 'sets user scope on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', scope: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'usr.scope' => 'bar')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', foo: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'usr.foo' => 'bar')
      end
    end

    it 'sets both explicit keywords and other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', email: 'foo@example.com', foo: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'usr.email' => 'foo@example.com', 'usr.foo' => 'bar')
      end
    end

    it 'enforces :id presence' do
      trace_op.measure('root') do |_span, _trace|
        expect { described_class.set_user(trace_op, foo: 'bar') }.to raise_error(ArgumentError)
      end
    end

    it 'enforces :id value' do
      trace_op.measure('root') do |_span, _trace|
        expect { described_class.set_user(trace_op, id: nil, foo: 'bar') }.to raise_error(ArgumentError)
      end
    end

    it 'ignores nil user email on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', email: nil)
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'ignores nil user name on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', name: nil)
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'ignores nil user session id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', session_id: nil)
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'ignores nil user role on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', role: nil)
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'ignores nil user scope on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', scope: nil)
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'ignores nil other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', foo: nil)
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'does not clear user email on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', email: 'foo@example.com')
        described_class.set_user(trace_op, id: '42', email: nil)
        expect(span.tags).to include('usr.id' => '42', 'usr.email' => 'foo@example.com')
      end
    end

    it 'does not clear user name on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', name: 'bar')
        described_class.set_user(trace_op, id: '42', name: nil)
        expect(span.tags).to include('usr.id' => '42', 'usr.name' => 'bar')
      end
    end

    it 'does not clear user session id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', session_id: 'bar')
        described_class.set_user(trace_op, id: '42', session_id: nil)
        expect(span.tags).to include('usr.id' => '42', 'usr.session_id' => 'bar')
      end
    end

    it 'does not clear user role on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', role: 'bar')
        described_class.set_user(trace_op, id: '42', role: nil)
        expect(span.tags).to include('usr.id' => '42', 'usr.role' => 'bar')
      end
    end

    it 'does not clear user scope on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', scope: 'bar')
        described_class.set_user(trace_op, id: '42', scope: nil)
        expect(span.tags).to include('usr.id' => '42', 'usr.scope' => 'bar')
      end
    end

    it 'does not clear other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.set_user(trace_op, id: '42', foo: 'bar')
        described_class.set_user(trace_op, id: '42', foo: nil)
        expect(span.tags).to include('usr.id' => '42', 'usr.foo' => 'bar')
      end
    end

    it 'enforces String value on id' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 42) }.to raise_error(TypeError)
      end
    end

    it 'enforces String value on email' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 'foo', email: 42) }.to raise_error(TypeError)
      end
    end

    it 'enforces String value on name' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 'foo', name: 42) }.to raise_error(TypeError)
      end
    end

    it 'enforces String value on session_id' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 'foo', session_id: 42) }.to raise_error(TypeError)
      end
    end

    it 'enforces String value on role' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 'foo', role: 42) }.to raise_error(TypeError)
      end
    end

    it 'enforces String value on scope' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 'foo', scope: 42) }.to raise_error(TypeError)
      end
    end

    it 'enforces String value on other keys' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 42, foo: 42) }.to raise_error(TypeError)
      end
    end

    context 'appsec' do
      before do
        allow(processor).to receive(:new_runner).and_return(instance_double(Datadog::AppSec::SecurityEngine::Runner))
        allow(Datadog::AppSec).to receive(:active_context).and_return(appsec_active_context)
      end

      let(:processor) { instance_double(Datadog::AppSec::Processor) }
      let(:appsec_active_context) { nil }

      context 'when is enabled' do
        before { Datadog.configuration.appsec.enabled = true }
        after { Datadog.configuration.reset! }

        let(:span_op) { trace_op.build_span('root') }
        let(:appsec_active_context) { Datadog::AppSec::Context.new(trace_op, span_op, processor) }

        it 'sets collection mode to SDK' do
          trace_op.measure('root') do |_span, _trace|
            described_class.set_user(trace_op, id: '42')
            expect(span_op.tags).to include('_dd.appsec.user.collection_mode' => 'sdk')
          end
        end

        it 'instruments the user information to appsec' do
          expect_any_instance_of(Datadog::AppSec::Instrumentation::Gateway).to receive(:push).with(
            'identity.set_user',
            instance_of(Datadog::AppSec::Instrumentation::Gateway::User)
          )

          described_class.set_user(trace_op, id: '42')
        end
      end

      context 'when is disabled' do
        it 'does not instrument the user information to appsec' do
          expect_any_instance_of(Datadog::AppSec::Instrumentation::Gateway).to_not receive(:push).with('identity.set_user')

          trace_op.measure('root') do
            described_class.set_user(trace_op, id: '42')
          end
        end
      end
    end

    context 'when tracing disabled' do
      it 'does mark trace for keeping' do
        expect(Datadog::Tracing.active_trace).to_not receive(:keep!)
        expect do
          described_class.set_user(id: '42')
        end.to_not raise_error
      end
    end
  end
end
