# typed: false

require_relative 'rails_helper'
require_relative '../analytics_examples'

# Manually load the `RunnerCommand` class, since this file is only loaded
# by Rails during the execution of `rails runner`.
# In a `rails runner` execution, the `RunnerCommand` class is loaded and then
# Rails immediately loads the Rails application, which calls `Datadog.configure`: https://github.com/rails/rails/blob/ad858b91a9a4bc94950708955e44c654a1f3789b/railties/lib/rails/commands/runner/runner_command.rb#L30
require 'rails/commands/runner/runner_command' if Rails.version >= '5.1'

RSpec.describe Datadog::Tracing::Contrib::Rails::Runner, execute_in_fork: Rails.version.to_i >= 8 do
  include_context 'Rails test application'

  subject(:run) { ::Rails::Command.invoke 'runner', argv }
  let(:argv) { [input] }
  let(:input) {}
  let(:source) { 'print "OK"' }

  let(:configuration_options) { {} }
  let(:span) do
    expect(spans).to have(1).item
    spans.first
  end

  before do
    skip('Rails runner tracing is not supported on Rails < 5.1') if Rails.version < '5.1'

    Datadog.configure do |c|
      c.tracing.instrument :rails, **configuration_options
    end

    app
  end

  shared_context 'with a custom service name' do
    context 'with a custom service name' do
      let(:configuration_options) { { service_name: 'runner-name' } }

      it 'sets the span service name' do
        expect { run }.to output('OK').to_stdout
        expect(span.service).to eq('runner-name')
      end
    end
  end

  shared_context 'with source code too long' do
    context 'with source code too long' do
      let(:source) { '123.to_i;' * 512  } # 4096-long string: 8 characters * 512

      it 'truncates source tag to 4096 characters, with "..." at the end' do
        run
        expect(span.get_tag('source').size).to eq(4096)
        expect(span.get_tag('source')).to start_with(source[0..(4096 - 3 - 1)]) # 3 fewer chars due to the appended '...'
        expect(span.get_tag('source')).to end_with('...') # The appended '...'
      end
    end
  end

  context 'with a file path' do
    around do |example|
      Tempfile.open('empty-file') do |file|
        @file_path = file.path
        file.write(source)
        file.flush

        example.run
      end
    end

    let(:file_path) { @file_path }
    let(:input) { file_path }

    it 'creates span for a file runner' do
      expect { run }.to output('OK').to_stdout

      expect(span.name).to eq('rails.runner.file')
      expect(span.resource).to eq(file_path)
      expect(span.service).to eq(tracer.default_service)
      expect(span.get_tag('source')).to eq('print "OK"')
      expect(span.get_tag('component')).to eq('rails')
      expect(span.get_tag('operation')).to eq('runner.file')
    end

    include_context 'with a custom service name'
    include_context 'with source code too long'

    it_behaves_like 'analytics for integration', ignore_global_flag: false do
      let(:source) { '' }
      before { run }
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    context 'with an error reading the source file' do
      before do
        # Make the file unreadable
        File.chmod(0o000, file_path)
      end

      it 'creates an error span' do
        expect { run }.to raise_error(LoadError)

        expect(span.name).to eq('rails.runner.file')
        expect(span.resource).to eq(file_path)
        expect(span.service).to eq(tracer.default_service)
        expect(span.get_tag('source')).to be_nil
        expect(span.get_tag('component')).to eq('rails')
        expect(span.get_tag('operation')).to eq('runner.file')
        expect(span).to have_error
        expect(span).to have_error_type('LoadError')
      end
    end
  end

  context 'from STDIN' do
    before do
      skip('Rails Runner in Rails 5.1 does not support STDIN') if Rails.version < '5.2'
    end

    around do |example|
      begin
        stdin = $stdin
        $stdin = StringIO.new(source)
        example.run
      ensure
        $stdin = stdin
      end
    end

    let(:input) { '-' }

    it 'creates span for an STDIN runner' do
      expect { run }.to output('OK').to_stdout

      expect(span.name).to eq('rails.runner.stdin')
      expect(span.resource).to eq('rails.runner.stdin') # Fallback to span#name
      expect(span.service).to eq(tracer.default_service)
      expect(span.get_tag('source')).to eq('print "OK"')
      expect(span.get_tag('component')).to eq('rails')
      expect(span.get_tag('operation')).to eq('runner.stdin')
    end

    include_context 'with a custom service name'
    include_context 'with source code too long'

    it_behaves_like 'analytics for integration', ignore_global_flag: false do
      let(:source) { '' }
      before { run }
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end
  end

  context 'from an inline code snippet' do
    let(:input) { source }

    it 'creates span for an inline code snippet' do
      expect { run }.to output('OK').to_stdout

      expect(span.name).to eq('rails.runner.inline')
      expect(span.resource).to eq('rails.runner.inline') # Fallback to span#name
      expect(span.service).to eq(tracer.default_service)
      expect(span.get_tag('source')).to eq('print "OK"')
      expect(span.get_tag('component')).to eq('rails')
      expect(span.get_tag('operation')).to eq('runner.inline')
    end

    context "when a current span isn't detected" do
      it "doesn't error when a span can't be identified to set the source tag on" do
        allow(Datadog::Tracing).to receive(:active_span).and_return(nil)

        expect { run }.to output('OK').to_stdout
      end
    end

    include_context 'with a custom service name'
    include_context 'with source code too long'

    it_behaves_like 'analytics for integration', ignore_global_flag: false do
      let(:source) { '' }
      before { run }
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end
  end
end
