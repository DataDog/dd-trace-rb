# typed: false

RSpec.describe Datadog::Profiling::TagBuilder do
  describe '.call' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    subject(:call) { described_class.call(settings: settings) }

    it 'returns a hash with the tags to be attached to a profile' do
      expect(call).to include(
        'host' => Datadog::Core::Environment::Socket.hostname,
        'language' => 'ruby',
        'pid' => Process.pid.to_s,
        'profiler_version' => start_with('1.'),
        'runtime' => 'ruby',
        'runtime_engine' => RUBY_ENGINE,
        'runtime-id' => Datadog::Core::Environment::Identity.id,
        'runtime_platform' => RUBY_PLATFORM,
        'runtime_version' => RUBY_VERSION,
      )
    end

    describe 'unified service tagging' do
      [:env, :service, :version].each do |tag|
        context "when a #{tag} is defined" do
          before do
            settings.send("#{tag}=".to_sym, 'expected_value')
          end

          it 'includes it as a tag' do
            expect(call).to include(tag.to_s => 'expected_value')
          end
        end

        context "when #{tag} is nil" do
          before do
            settings.send("#{tag}=".to_sym, nil)
          end

          it do
            expect(call.keys).to_not include(tag.to_s)
          end
        end
      end
    end

    it 'includes the provided user tags' do
      settings.tags = { 'foo' => 'bar' }

      expect(call).to include('foo' => 'bar')
    end

    context 'when there is a conflict between user and metadata tags' do
      it 'overrides the user-provided tags' do
        settings.tags = { 'foo' => 'bar', 'language' => 'python' }

        expect(call).to include('foo' => 'bar', 'language' => 'ruby')
      end
    end
  end
end
