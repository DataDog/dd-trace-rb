require 'spec_helper'
require 'datadog/core/environment/process'
require 'open3'

RSpec.describe Datadog::Core::Environment::Process do
  describe '::serialized' do
    subject(:serialized) { described_class.serialized }

    def with_process_env(program_name:, pwd: nil)
      original_0 = $0
      original_pwd = Dir.pwd
      $0 = program_name
      allow(Dir).to receive(:pwd).and_return(pwd) if pwd
      reset_serialized!

      yield
    ensure
      $0 = original_0
      allow(Dir).to receive(:pwd).and_return(original_pwd) if pwd
      reset_serialized!
    end

    def reset_serialized!
      described_class.remove_instance_variable(:@serialized) if described_class.instance_variable_defined?(:@serialized)
    end

    it { is_expected.to be_a_kind_of(String) }

    it 'returns the same object when called multiple times' do
      # Processes are fixed so no need to recompute this on each call
      first_call = described_class.serialized
      second_call = described_class.serialized
      expect(first_call).to equal(second_call)
    end

    it 'uses the basedir for /expectedbasedir/executable' do
      with_process_env(program_name: '/expectedbasedir/executable', pwd: '/app') do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:executable')
        expect(described_class.serialized).to include('entrypoint.basedir:expectedbasedir')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    it 'uses the basedir for irb' do
      with_process_env(program_name: 'irb', pwd: '/app') do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:irb')
        expect(described_class.serialized).to include('entrypoint.basedir:app')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    it 'uses the basedir for my/path/rubyapp.rb' do
      with_process_env(program_name: 'my/path/rubyapp.rb', pwd: '/app') do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:rubyapp.rb')
        expect(described_class.serialized).to include('entrypoint.basedir:path')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end

    it 'uses the basedir for bin/rails s' do
      with_process_env(program_name: 'bin/rails s', pwd: '/app') do
        expect(described_class.serialized).to include('entrypoint.workdir:app')
        expect(described_class.serialized).to include('entrypoint.name:rails_s')
        expect(described_class.serialized).to include('entrypoint.basedir:bin')
        expect(described_class.serialized).to include('entrypoint.type:script')
      end
    end
  end

  describe 'Scenario: Real applications' do
    skip_unless_integration_testing_enabled

    context 'when running a real Rails application' do
      it 'detects Rails process information correctly' do
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
