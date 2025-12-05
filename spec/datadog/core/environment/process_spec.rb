require 'spec_helper'
require 'datadog/core/environment/process'
require 'open3'

RSpec.describe Datadog::Core::Environment::Process do
  describe '::serialized' do
    subject(:serialized) { described_class.serialized }

    def reset_serialized!
      described_class.remove_instance_variable(:@serialized) if described_class.instance_variable_defined?(:@serialized)
    end

    shared_context 'with mocked process environment' do
      let(:pwd) { '/app' }

      around do |example|
        @original_0 = $0
        $0 = program_name
        example.run
        $0 = @original_0
      end

      before do
        allow(Dir).to receive(:pwd).and_return(pwd)
        allow(File).to receive(:expand_path).and_call_original
        allow(File).to receive(:expand_path).with('.').and_return('/app')
        reset_serialized!
      end

      after do
        reset_serialized!
      end
    end

    it { is_expected.to be_a_kind_of(String) }

    it 'returns the same object when called multiple times' do
      # Processes are fixed so no need to recompute this on each call
      first_call = described_class.serialized
      second_call = described_class.serialized
      expect(first_call).to equal(second_call)
    end

    context 'with /expectedbasedir/executable' do
      include_context 'with mocked process environment'
      let(:program_name) { '/expectedbasedir/executable' }

      it 'uses the basedir correctly' do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:executable')
        expect(described_class.serialized).to include('entrypoint.basedir:expectedbasedir')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    context 'with irb' do
      include_context 'with mocked process environment'
      let(:program_name) { 'irb' }

      it 'uses the basedir correctly' do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:irb')
        expect(described_class.serialized).to include('entrypoint.basedir:app')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    context 'with my/path/rubyapp.rb' do
      include_context 'with mocked process environment'
      let(:program_name) { 'my/path/rubyapp.rb' }

      it 'extracts out serialized tags correctly' do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:rubyapp.rb')
        expect(described_class.serialized).to include('entrypoint.basedir:path')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    context 'with my/path/foo:,bar' do
      include_context 'with mocked process environment'
      let(:program_name) { 'my/path/foo:,bar' }

      it 'extracts out serialized tags correctly' do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:foo_bar')
        expect(described_class.serialized).to include('entrypoint.basedir:path')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    context 'with bin/rails' do
      include_context 'with mocked process environment'
      let(:program_name) { 'bin/rails' }

      it 'extracts out serialized tags correctly' do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:rails')
        expect(described_class.serialized).to include('entrypoint.basedir:bin')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end
  end

  describe 'Scenario: Real applications' do
    skip_unless_integration_testing_enabled

    context 'when running a real Rails application' do
      before do
        skip 'Rails 8 is only supported on CRuby' unless PlatformHelpers.mri?
      end

      it 'detects Rails process information correctly', ruby: '>= 3.2' do
        project_root_directory = Dir.pwd

        Dir.mktmpdir do |tmp_dir|
          Dir.chdir(tmp_dir) do
            Bundler.with_unbundled_env do
              _, _, _ = Open3.capture3('rails new test@_app --minimal --skip-active-record --skip-test --skip-keeps --skip-git --skip-docker')
              expect(File.exist?("test@_app/Gemfile")).to be true
            end

            File.open("test@_app/Gemfile", 'a') do |file|
              file.puts "gem 'datadog', path: '#{project_root_directory}', require: false"
            end
            File.write("test@_app/config/initializers/process_initializer.rb", <<-RUBY)
                        Rails.application.config.after_initialize do
                            require 'datadog/core/environment/process'
                            STDERR.puts "_dd.tags.process:\#{Datadog::Core::Environment::Process.serialized}"
                            STDERR.flush
                            Thread.new { Process.kill('TERM', Process.pid) }
                        end
            RUBY

            Bundler.with_unbundled_env do
              Dir.chdir("test@_app") do
                _, _, _ = Open3.capture3('bundle install')
                _, err, _ = Open3.capture3('bundle exec rails s')
                expect(err).to include('entrypoint.workdir:test_app')
                expect(err).to include('entrypoint.type:script')
                expect(err).to include('entrypoint.name:rails')
                expect(err).to include('entrypoint.basedir:bin')
              end
            end
          end
        end
      end
    end
  end
end
