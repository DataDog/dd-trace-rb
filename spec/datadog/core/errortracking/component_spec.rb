require 'spec_helper'
require 'datadog/core/errortracking/component'

RSpec.describe Datadog::Core::Errortracking::Component do
  let(:tracer) { new_tracer(enabled: false) }
  let(:spans) { tracer.writer.spans(:keep) }
  let(:logger) { Logger.new($stdout) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }

  describe '.build_errortracking_component' do
    context 'when errortracking is deactivated' do
      it 'returns nil' do
        expect(described_class.build(settings, tracer)).to be_nil
      end
    end

    context 'when a wrong argument is passed' do
      before { settings.errortracking.to_instrument = 'foo' }
      it 'returns nil' do
        expect(described_class.build(settings, tracer)).to be_nil
      end
    end

    shared_examples 'it creates and starts a component' do
      it 'creates and starts a component' do
        component = instance_double(described_class)
        allow(described_class).to receive(:new).and_return(component)
        allow(component).to receive(:start).and_return(nil)

        result = described_class.build(settings, tracer)

        expect(result).to eq(component)
        expect(component).to have_received(:start)
      end
    end

    context 'when to_instrument is provided' do
      before { settings.errortracking.to_instrument = 'all' }
      include_examples 'it creates and starts a component'
    end

    context 'when to_instrument_modules is provided' do
      before { settings.errortracking.to_instrument_modules = ['rails'] }
      include_examples 'it creates and starts a component'
    end

    context 'when all required parameters are provided' do
      before do
        settings.errortracking.to_instrument_modules = ['rails']
        settings.errortracking.to_instrument = 'user'
      end
      include_examples 'it creates and starts a component'
    end
  end

  describe 'use errortracking component global feature' do
    before do
      settings.errortracking.to_instrument = 'all'
      @errortracker = described_class.build(settings, tracer)
      tracer.enabled = true
    end

    after do
      tracer.shutdown!
      @errortracker.stop
    end

    shared_examples 'captures exception details' do |exception_count|
      it "captures exception(s) with correct details" do
        expect(span.events.length).to eq(expected_exceptions.length)

        span.events.each_with_index do |event, index|
          expect(event.attributes['type']).to eq(expected_exceptions[index][:type])
          expect(event.attributes['message']).to eq(expected_exceptions[index][:message])
        end
      end
    end

    context 'with a simple begin-rescue block' do
      let!(:span) do
        tracer.trace('operation') do |inner_span|
          begin
            raise 'this is an exception'
          rescue
          end
          inner_span.finish
        end
      end

      let(:expected_exceptions) do
        [{ type: 'RuntimeError', message: 'this is an exception' }]
      end

      include_examples 'captures exception details'
    end

    context 'with multiple begin-rescue blocks' do
      let!(:span) do
        tracer.trace('operation') do |inner_span|
          begin
            raise 'this is an exception'
          rescue
          end
          begin
            raise StandardError, 'this is another exception'
          rescue
          end
          inner_span.finish
        end
      end

      let(:expected_exceptions) do
        [
          { type: 'RuntimeError', message: 'this is an exception' },
          { type: 'StandardError', message: 'this is another exception' }
        ]
      end

      include_examples 'captures exception details'
    end

    context 'with nested begin-rescue blocks' do
      let!(:span) do
        tracer.trace('operation') do |inner_span|
          begin
            raise 'this is an exception'
          rescue
            begin
              raise 'this is another exception'
            rescue
            end
          end
          inner_span.finish
        end
      end

      let(:expected_exceptions) do
        [
          { type: 'RuntimeError', message: 'this is an exception' },
          { type: 'RuntimeError', message: 'this is another exception' }
        ]
      end

      include_examples 'captures exception details'
    end

    context 'when an exception is raised multiple times' do
      let!(:span) do
        tracer.trace('operation') do |inner_span|
          begin
            begin
              raise 'this is an exception'
            rescue StandardError => e
              raise e
            end
          rescue
          end
          inner_span.finish
        end
      end

      let(:expected_exceptions) do
        [{ type: 'RuntimeError', message: 'this is an exception' }]
      end

      include_examples 'captures exception details'
    end
  end

  shared_examples 'error tracking behavior' do |instrument_setting = nil, modules_to_instrument = [], expected_errors = []|
    before(:all) do
      @gem_root, @gem_lib_dir = ErrortrackingHelpers.generate_test_env
    end

    after(:all) do
      # Clean up
      $LOAD_PATH.delete(@gem_lib_dir)
      FileUtils.remove_entry(@gem_root) if @gem_root && Dir.exist?(@gem_root)
    end

    before do
      # Configure settings based on test parameters
      settings.errortracking.to_instrument = instrument_setting if instrument_setting
      settings.errortracking.to_instrument_modules = modules_to_instrument if modules_to_instrument.any?

      @errortracker = described_class.build(settings, tracer)

      # Require the mock gem files
      require 'mock_gem'

      # Require all the test modules
      require_relative 'lib1'
      require_relative './lib2'
      require_relative './sublib/sublib1'
      require_relative './sublib/sublib2'

      tracer.enabled = true

      allow(Gem::Specification).to receive(:find_by_name).with('mock-gem').and_return(true)
    end

    after do
      $LOADED_FEATURES.reject! { |path| path.include?('mock_gem') }
      Object.send(:remove_const, :MockGem) if defined?(MockGem)

      @errortracker.stop
      tracer.shutdown!
    end

    it 'tracks errors according to settings' do
      span = tracer.trace('operation') do |inner_span|
        begin
          raise 'user code error'
        rescue
        end

        MockGem::Client.rescue_error
        MockGem::Utils.rescue_error
        Lib1.rescue_error
        Lib2.rescue_error
        SubLib1.rescue_error
        SubLib2.rescue_error

        inner_span.finish
      end

      if expected_errors.any?
        # For module-specific tests
        expect(span.events.length).to eq(expected_errors.length)
        event_messages = span.events.map { |e| e.attributes['message'] }
        expected_errors.each do |error|
          expect(event_messages).to include(error)
        end
      end
    end
  end

  describe 'use errortracking component with different settings' do
    context 'when tracking user code only' do
      include_examples 'error tracking behavior',
        'user',
        [],
        ['user code error', 'lib1 error', 'lib2 error', 'sublib1 error', 'sublib2 error']
    end

    context 'when tracking third_party code' do
      include_examples 'error tracking behavior', 'third_party', [], ['mock_gem client error', 'mock_gem utils error']
    end

    context 'when tracking all code' do
      include_examples 'error tracking behavior',
        'all',
        [],
        ['mock_gem client error', 'mock_gem utils error', 'user code error', 'lib1 error', 'lib2 error', 'sublib1 error',
         'sublib2 error']
    end
  end

  describe 'use errortracking component with module-specific settings' do
    context "when instrumenting ['lib1']" do
      include_examples 'error tracking behavior', nil, ['lib1'], ['lib1 error']
    end

    context "when instrumenting ['sublib']" do
      include_examples 'error tracking behavior', nil, ['sublib'], ['sublib1 error', 'sublib2 error']
    end

    context "when instrumenting ['sublib1', 'lib1']" do
      include_examples 'error tracking behavior', nil, ['sublib1', 'lib1'], ['sublib1 error', 'lib1 error']
    end

    context "when instrumenting ['sublib', 'lib1']" do
      include_examples 'error tracking behavior', nil, ['sublib', 'lib1'], ['lib1 error', 'sublib1 error', 'sublib2 error']
    end
  end

  describe 'use errortracking component with gem-specific settings' do
    context "when instrumenting ['mock_gem/client']" do
      include_examples 'error tracking behavior', nil, ['mock_gem/client'], ['mock_gem client error']
    end

    context "when instrumenting ['mock_gem']" do
      include_examples 'error tracking behavior', nil, ['mock_gem'], ['mock_gem client error', 'mock_gem utils error']
    end
  end

  describe 'use errortracking component with combined user and module settings' do
    context "when tracking user code and instrumenting ['mock_gem/client']" do
      include_examples 'error tracking behavior',
        'user',
        ['mock_gem/client'],
        ['user code error', 'lib1 error', 'lib2 error', 'sublib1 error', 'sublib2 error', 'mock_gem client error']
    end
  end
end
