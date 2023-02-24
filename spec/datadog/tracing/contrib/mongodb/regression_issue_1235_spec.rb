require 'ddtrace'
require 'mongo'

RSpec.describe 'Mongo crash regression #1235' do
  before { skip unless PlatformHelpers.mri? }

  let(:client) { Mongo::Client.new(["#{host}:#{port}"], client_options) }
  let(:client_options) { { database: database } }
  let(:host) { ENV.fetch('TEST_MONGODB_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_MONGODB_PORT', 27017).to_i }
  let(:database) { 'test' }

  before do
    # Disable Mongo logging
    Mongo::Logger.logger.level = ::Logger::WARN

    Datadog.configure do |c|
      c.tracing.instrument :mongo
    end
  end

  subject do
    # CRuby returns a successful status code even during a crash,
    # which makes testing this bug much harder.
    # We resort to capturing STDERR and inspecting for errors.

    pid = fork do
      # Suppress all errors during Ruby instruction execution.
      # When the VM is shutting down, this StringIO
      # will be destroy, allowing the crash output to be
      # outputted to STDERR.
      $stderr = StringIO.new

      client[:foo].insert_one(bar: 'baz')

      exit(true) # Forcing an immediate Ruby VM exit causes the crash
    end

    _, status = Process.waitpid2(pid)
    status
  end

  it 'does not crash on exit' do
    expect { subject }.to_not output(/^\[BUG\] /).to_stderr_from_any_process

    expect(subject).to be_success
  end
end
