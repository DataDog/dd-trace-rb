require 'spec_helper'
require 'datadog/core/environment/process'
require 'open3'

RSpec.describe Datadog::Core::Environment::Process do
  describe '::serialized' do
    subject(:serialized) { described_class.serialized }

    it { is_expected.to be_a_kind_of(String) }

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

    context 'when Rails application name is available' do
      include_context 'with mocked process environment'
      let(:program_name) { 'bin/rails' }

      before do
        described_class.rails_application_name = 'Test::App'
      end

      after do
        described_class.rails_application_name = nil
      end

      it 'includes rails.application in serialized tags' do
        expect(serialized).to include('rails.application:test_app')
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
                        require 'datadog'
                        Datadog.configure { }
                        ActiveSupport.on_load(:after_initialize) do
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
                expect(err).to include('rails.application:test_app')
              end
            end
          end
        end
      end
    end
  end

  describe '::tags' do
    subject(:tags) { described_class.tags }

    it { is_expected.to be_a_kind_of(Array) }

    it 'is an array of strings' do
      expect(tags).to all(be_a(String))
    end

    context 'with /expectedbasedir/executable' do
      include_context 'with mocked process environment'
      let(:program_name) { '/expectedbasedir/executable' }

      it 'extracts out the tag array correctly' do
        expect(tags.length).to eq(4)
        expect(described_class.tags).to include('entrypoint.workdir:app')
        expect(described_class.tags).to include('entrypoint.name:executable')
        expect(described_class.tags).to include('entrypoint.basedir:expectedbasedir')
        expect(described_class.tags).to include('entrypoint.type:script')
      end
    end

    context 'with irb' do
      include_context 'with mocked process environment'
      let(:program_name) { 'irb' }

      it 'extracts out the tag array correctly' do
        expect(tags.length).to eq(4)
        expect(described_class.tags).to include('entrypoint.workdir:app')
        expect(described_class.tags).to include('entrypoint.name:irb')
        expect(described_class.tags).to include('entrypoint.basedir:app')
        expect(described_class.tags).to include('entrypoint.type:script')
      end
    end

    context 'with my/path/rubyapp.rb' do
      include_context 'with mocked process environment'
      let(:program_name) { 'my/path/rubyapp.rb' }

      it 'extracts out the tag array correctly' do
        expect(tags.length).to eq(4)
        expect(described_class.tags).to include('entrypoint.workdir:app')
        expect(described_class.tags).to include('entrypoint.name:rubyapp.rb')
        expect(described_class.tags).to include('entrypoint.basedir:path')
        expect(described_class.tags).to include('entrypoint.type:script')
      end
    end

    context 'with my/path/foo:,bar' do
      include_context 'with mocked process environment'
      let(:program_name) { 'my/path/foo:,bar' }

      it 'extracts out the tag array correctly' do
        expect(tags.length).to eq(4)
        expect(described_class.tags).to include('entrypoint.workdir:app')
        expect(described_class.tags).to include('entrypoint.name:foo_bar')
        expect(described_class.tags).to include('entrypoint.basedir:path')
        expect(described_class.tags).to include('entrypoint.type:script')
      end
    end

    context 'with bin/rails' do
      include_context 'with mocked process environment'
      let(:program_name) { 'bin/rails' }

      it 'extracts out the tags array correctly' do
        expect(tags.length).to eq(4)
        expect(described_class.tags).to include('entrypoint.workdir:app')
        expect(described_class.tags).to include('entrypoint.name:rails')
        expect(described_class.tags).to include('entrypoint.basedir:bin')
        expect(described_class.tags).to include('entrypoint.type:script')
      end
    end

    context 'when Rails application name is available' do
      include_context 'with mocked process environment'
      let(:program_name) { 'bin/rails' }

      before { described_class.rails_application_name = 'test_app' }
      after { described_class.rails_application_name = nil }

      it 'includes rails.application in tag array' do
        expect(tags.length).to eq(5)
        expect(tags).to include('rails.application:test_app')
      end
    end
  end

  describe '::set_service' do
    include_context 'with mocked process environment'
    let(:program_name) { 'bin/rails' }

    context 'when service is user-configured' do
      before { described_class.set_service('myapp', user_configured: true) }

      it 'includes svc.user:true in tags' do
        expect(described_class.tags).to include('svc.user:true')
      end

      it 'does not include svc.auto in tags' do
        expect(described_class.tags.join(',')).not_to include('svc.auto')
      end

      it 'includes svc.user:true in serialized' do
        expect(described_class.serialized).to include('svc.user:true')
      end
    end

    context 'when service is not user-configured (fallback)' do
      before { described_class.set_service('rails', user_configured: false) }

      it 'includes svc.auto with the fallback service name in tags' do
        expect(described_class.tags).to include('svc.auto:rails')
      end

      it 'does not include svc.user in tags' do
        expect(described_class.tags.join(',')).not_to include('svc.user')
      end

      it 'includes svc.auto with the fallback service name in serialized' do
        expect(described_class.serialized).to include('svc.auto:rails')
      end
    end

    context 'when set_service is called multiple times' do
      it 'reflects the most recent value' do
        described_class.set_service('first', user_configured: false)
        described_class.set_service('myapp', user_configured: true)
        expect(described_class.tags).to include('svc.user:true')
        expect(described_class.tags.join(',')).not_to include('svc.auto')
      end
    end

    context 'when set_service has not been called' do
      it 'omits service tags entirely' do
        expect(described_class.tags.join(',')).not_to include('svc.')
      end
    end
  end

  describe '::rails_application_name=' do
    include_context 'with mocked process environment'
    let(:program_name) { 'bin/rails' }

    after do
      described_class.rails_application_name = nil
    end

    it 'includes the rails app name in the tags' do
      described_class.rails_application_name = "Test::App"
      expect(described_class.tags).to include('rails.application:test_app')
    end

    it 'is reflected in subsequent calls to tags' do
      described_class.tags
      described_class.rails_application_name = "Test::App"
      expect(described_class.tags).to include('rails.application:test_app')
    end

    it 'is reflected in subsequent calls to serialized' do
      described_class.serialized
      described_class.rails_application_name = "Test::App"
      expect(described_class.serialized).to include('rails.application:test_app')
    end
  end
end
