require 'spec_helper'

require 'time'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/identity'

RSpec.describe Datadog::Kit::Identity do
  subject(:trace_op) { Datadog::Tracing::TraceOperation.new }

  describe '#set_user' do
    it 'sets user id on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'sets user email on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', email: 'foo@example.com')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.email' => 'foo@example.com')
    end

    it 'sets user name on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', name: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.name' => 'bar')
    end

    it 'sets user session id on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', session_id: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.session_id' => 'bar')
    end

    it 'sets user role on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', role: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.role' => 'bar')
    end

    it 'sets user scope on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', scope: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.scope' => 'bar')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', foo: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.foo' => 'bar')
    end

    it 'sets both explicit keywords and other keys on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', email: 'foo@example.com', foo: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.email' => 'foo@example.com', 'usr.foo' => 'bar')
    end

    it 'enforces :id presence' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, foo: 'bar') }.to raise_error(ArgumentError)
      end
    end

    it 'enforces :id value' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: nil, foo: 'bar') }.to raise_error(ArgumentError)
      end
    end

    it 'ignores nil user email on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', email: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'ignores nil user name on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', name: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'ignores nil user session id on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', session_id: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'ignores nil user role on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', role: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'ignores nil user scope on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', scope: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'ignores nil other keys on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', foo: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'does not clear user email on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', email: 'foo@example.com')
        described_class.set_user(trace_op, id: '42', email: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.email' => 'foo@example.com')
    end

    it 'does not clear user name on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', name: 'bar')
        described_class.set_user(trace_op, id: '42', name: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.name' => 'bar')
    end

    it 'does not clear user session id on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', session_id: 'bar')
        described_class.set_user(trace_op, id: '42', session_id: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.session_id' => 'bar')
    end

    it 'does not clear user role on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', role: 'bar')
        described_class.set_user(trace_op, id: '42', role: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.role' => 'bar')
    end

    it 'does not clear user scope on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', scope: 'bar')
        described_class.set_user(trace_op, id: '42', scope: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.scope' => 'bar')
    end

    it 'does not clear other keys on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42', foo: 'bar')
        described_class.set_user(trace_op, id: '42', foo: nil)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'usr.foo' => 'bar')
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
      after { Datadog.configuration.appsec.send(:reset!) }

      context 'when is enabled' do
        it 'instruments the user information to appsec' do
          Datadog.configuration.appsec.enabled = true
          user = OpenStruct.new(id: '42')
          expect_any_instance_of(Datadog::AppSec::Instrumentation::Gateway).to receive(:push).with(
            'identity.set_user',
            user
          )
          described_class.set_user(trace_op, id: '42')
        end
      end

      context 'when is disabled' do
        it 'does not instrument the user information to appsec' do
          Datadog.configuration.appsec.enabled = false
          expect_any_instance_of(Datadog::AppSec::Instrumentation::Gateway).to_not receive(:push).with('identity.set_user')
          described_class.set_user(trace_op, id: '42')
        end
      end
    end
  end
end
