# typed: false

require_relative 'rails_helper'
require_relative '../analytics_examples'

RSpec.describe Datadog::Tracing::Contrib::Rails::Runner do
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
    Datadog.configure do |c|
      c.tracing.instrument :rails, **configuration_options
    end

    app
  end

  shared_context 'with a custom service name' do
    context 'with a custom service name' do
      let(:configuration_options) { { runner_service_name: 'runner-name' } }

      it 'sets the span service name' do
        run
        expect(span.service).to eq('runner-name')
      end
    end
  end

  shared_context 'with source code too long' do
    context 'with source code too long' do
      # Valid, non-trivial Ruby code to avoid the warning "possibly useless use of a literal in void context".
      let(:source) { '0' * 4096 + '.to_int' }

      it 'truncates source tag to 4096 characters' do
        run
        expect(span.get_tag('source').size).to eq(4096)
        expect(span.get_tag('source')).to start_with(source[0..4092]) # 3 fewer characters due to the appended '...'
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
  end

  context 'from STDIN' do
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
