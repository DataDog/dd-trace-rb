require 'datadog/error_tracking/spec_helper'
require 'datadog/error_tracking/component'

RSpec.describe Datadog::ErrorTracking::Component do
  error_tracking_test

  let(:tracer) { new_tracer(enabled: false) }
  let(:spans) { tracer.writer.spans(:keep) }
  let(:logger) { Logger.new($stdout) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }

  describe '.build_errortracking_component' do
    context 'when ErrorTracking is deactivated' do
      it 'returns nil' do
        expect(described_class.build(settings, tracer, logger)).to be_nil
      end
    end

    context 'when a wrong argument is passed' do
      before { settings.error_tracking.handled_errors = 'foo' }
      it 'returns nil' do
        expect(described_class.build(settings, tracer, logger)).to be_nil
      end
    end

    shared_examples 'it creates and starts a component' do
      it 'creates a properly configured component and starts it' do
        result = described_class.build(settings, tracer, logger)

        expect(result).to be_a(described_class)
        expect(result.send(:instance_variable_get, :@tracer)).to eq(tracer)
        expect(result.send(:instance_variable_get, :@handled_exc_tracker).enabled?).to be true
        if settings.error_tracking.handled_errors_include&.any?
          expect(result.send(:instance_variable_get, :@instrumented_files)).to be_a(Set)
          expect(result.send(:instance_variable_get, :@include_path_getter).enabled?).to be true
        end
      end
    end

    context 'when handled_errors is provided' do
      before { settings.error_tracking.handled_errors = 'all' }
      include_examples 'it creates and starts a component'
    end

    context 'when handled_errors_include is provided' do
      before { settings.error_tracking.handled_errors_include = ['rails'] }
      include_examples 'it creates and starts a component'
    end

    context 'when all required parameters are provided' do
      before do
        settings.error_tracking.handled_errors_include = ['rails']
        settings.error_tracking.handled_errors = 'user'
      end
      include_examples 'it creates and starts a component'
    end
  end

  describe 'use ErrorTracking component global feature' do
    before do
      settings.error_tracking.handled_errors = 'all'
      @errortracker = described_class.build(settings, tracer, logger)
      tracer.enabled = true
    end

    after do
      tracer.shutdown!
      @errortracker.shutdown!
    end

    shared_examples 'span event validation' do
      it 'has the expected span events' do
        expect(spans.count).to eq(expected_exceptions.count)
        expected_exceptions.each_with_index do |events_per_span, i|
          expect(spans[i].events.length).to eq(events_per_span.length)
          unless events_per_span.empty?
            expect(spans[i].get_tag(Datadog::ErrorTracking::Ext::SPAN_EVENTS_HAS_EXCEPTION)).to eq('true')
          end
          events_per_span.each_with_index do |event, j|
            expect(spans[i].events[j].attributes['exception.type']).to eq(event[:type])
            expect(spans[i].events[j].attributes['exception.message']).to eq(event[:message])
          end
        end
      end
    end

    # standard:disable Lint/UselessRescue
    context 'with a simple begin-rescue block' do
      let(:expected_exceptions) do
        [[{type: 'RuntimeError', message: 'this is an exception'}]]
      end

      before do
        tracer.trace('operation') do
          raise 'this is an exception'
        rescue
          # do nothing
        end
      end

      include_examples 'span event validation'
    end

    context 'with multiple begin-rescue blocks' do
      let(:expected_exceptions) do
        [[
          {type: 'RuntimeError', message: 'this is an exception'},
          {type: 'StandardError', message: 'this is another exception'}
        ]]
      end

      before do
        tracer.trace('operation') do
          begin
            raise 'this is an exception'
          rescue
            # do nothing
          end
          begin
            raise StandardError, 'this is another exception'
          rescue
            # do nothing
          end
        end
      end

      include_examples 'span event validation'
    end

    context 'when an exception is handled multiple times' do
      let(:expected_exceptions) do
        [[{type: 'RuntimeError', message: 'this is an exception'}]]
      end

      before do
        tracer.trace('operation') do
          begin
            raise 'this is an exception'
          rescue => e
            raise e
          end
        rescue
          # do nothing
        end
      end

      include_examples 'span event validation'
    end

    context 'when an exception is handled multiple times with different types' do
      let(:expected_exceptions) do
        [[
          {type: 'RuntimeError', message: 'this is an exception'},
          {type: 'KeyError', message: 'this is an exception'}
        ]]
      end

      before do
        tracer.trace('operation') do
          begin
            raise 'this is an exception'
          rescue => e
            raise KeyError, e
          end
        rescue
          # do nothing
        end
      end

      include_examples 'span event validation'
    end

    context 'when an exception is handled then raised' do
      let(:expected_exceptions) do
        [[]]
      end

      before do
        tracer.trace('operation') do |span|
          @span_op = span
          raise 'this is an exception'
        rescue
          raise
        end
      rescue
        # do nothing
      end

      include_examples 'span event validation'
    end

    context 'when number of span events is over limit' do
      let(:expected_exceptions) do
        [Array.new(100, {type: 'RuntimeError', message: 'this is an exception'})]
      end

      before do
        tracer.trace('operation') do
          101.times do
            raise 'this is an exception'
          rescue
            # do nothing
          end
        end
      end

      include_examples 'span event validation'
    end

    context 'when an exception is handled in the parent_span' do
      let(:expected_exceptions) do
        [[], [{type: 'RuntimeError', message: 'this is an exception'}]]
      end

      before do
        def parent_span
          tracer.trace('parent_span') do
            child_span
          rescue
            # do nothing
          end
        end

        def child_span
          tracer.trace('child_span') do
            raise 'this is an exception'
          rescue => e
            raise e
          end
        end

        parent_span
      end

      it 'has the correct span names' do
        expect(spans).to have(2).items
        expect(spans[0].name).to eq('child_span')
        expect(spans[1].name).to eq('parent_span')
      end

      include_examples 'span event validation'
    end
    # standard:enable Lint/UselessRescue
  end

  shared_examples 'error tracking behavior' do |instrument_setting = nil, handled_errors_include = [], expected_errors = []|
    before(:all) do
      @gem_root_dir = File.expand_path('../../fixtures/gems/mock-gem-2.1.1', __dir__)
      @gem_lib_dir = File.join(@gem_root_dir, 'lib')
      $LOAD_PATH.unshift(@gem_lib_dir) unless $LOAD_PATH.include?(@gem_lib_dir)

      # Create and register the mock gem specification
      mock_gemspec = Gem::Specification.new do |s|
        s.name = 'mock-gem'
        s.version = '2.1.1'
        s.loaded_from = File.join(@gem_root_dir, 'mock-gem.gemspec')
        s.full_gem_path = @gem_root_dir
      end
      Gem::Specification.add_spec(mock_gemspec)
    end

    after(:all) do
      $LOAD_PATH.delete(@gem_lib_dir)
      Gem::Specification.reset
    end

    before do
      # Configure settings based on test parameters
      settings.error_tracking.handled_errors = instrument_setting if instrument_setting
      settings.error_tracking.handled_errors_include = handled_errors_include if handled_errors_include.any?

      @errortracker = described_class.build(settings, tracer, logger)

      # Require the mock gem files
      require 'mock_gem'

      # Require all the test modules
      require_relative '../error_tracking/lib1'
      require_relative '../error_tracking/lib2'
      require_relative '../error_tracking/sublib/sublib1'
      require_relative '../error_tracking/sublib/sublib2'

      tracer.enabled = true
    end

    after do
      $LOADED_FEATURES.reject! do |path|
        path.include?('spec/datadog/error_tracking/lib') ||
          path.include?('spec/datadog/error_tracking/sublib') ||
          path.include?('mock_gem')
      end
      Object.send(:remove_const, :MockGem) if defined?(MockGem)
      Object.send(:remove_const, :Lib1) if defined?(Lib1)
      Object.send(:remove_const, :Lib2) if defined?(Lib2)
      Object.send(:remove_const, :SubLib1) if defined?(SubLib1)
      Object.send(:remove_const, :SubLib2) if defined?(SubLib2)

      @errortracker.shutdown!
      tracer.shutdown!
    end

    it 'tracks errors according to settings' do
      tracer.trace('operation') do
        begin
          raise 'user code error'
        rescue
          # do nothing
        end

        MockGem::Client.rescue_error
        MockGem::Utils.rescue_error
        Lib1.rescue_error
        Lib2.rescue_error
        SubLib1.rescue_error
        SubLib2.rescue_error
      end

      if expected_errors.any?
        span = spans[0]
        expect(span.events.length).to eq(expected_errors.length)
        event_messages = span.events.map { |e| e.attributes['exception.message'] }
        expected_errors.each do |error|
          expect(event_messages).to include(error)
        end
      end
    end
  end

  describe 'use ErrorTracking component with different settings' do
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

  describe 'use ErrorTracking component with module-specific settings' do
    context "when instrumenting ['lib1']" do
      include_examples 'error tracking behavior', nil, ['lib1'], ['lib1 error']
    end

    context "when instrumenting ['lib1'] with absolute exact path" do
      absolute_path = File.expand_path('./spec/datadog/error_tracking/lib1')
      include_examples 'error tracking behavior', nil, [absolute_path], ['lib1 error']
    end

    context "when instrumenting ['lib1'] with absolute exact path and .rb" do
      absolute_path = File.expand_path('./spec/datadog/error_tracking/lib1.rb')
      include_examples 'error tracking behavior', nil, [absolute_path], ['lib1 error']
    end

    context "when instrumenting ['lib1'] with abs path " do
      absolute_path = File.expand_path('./spec/datadog/error_tracking/sublib')
      include_examples 'error tracking behavior',
        nil,
        [absolute_path],
        ['sublib1 error', 'sublib2 error']
    end

    context "when instrumenting ['lib1'] with rel path" do
      include_examples 'error tracking behavior', nil, ['./spec/datadog/error_tracking/lib1'], ['lib1 error']
    end

    context "when instrumenting ['sublib']" do
      include_examples 'error tracking behavior', nil, ['sublib'], ['sublib1 error', 'sublib2 error']
    end

    context "when instrumenting ['sublib1', 'lib1']" do
      include_examples 'error tracking behavior', nil, ['sublib1', 'lib1.rb'], ['sublib1 error', 'lib1 error']
    end

    context "when instrumenting ['sublib', 'lib1']" do
      include_examples 'error tracking behavior',
        nil,
        ['error_tracking/sublib', 'lib1'],
        ['lib1 error', 'sublib1 error', 'sublib2 error']
    end
  end

  describe 'use ErrorTracking component with gem-specific settings' do
    context "when instrumenting ['mock_gem/client']" do
      include_examples 'error tracking behavior', nil, ['mock_gem/client'], ['mock_gem client error']
    end

    context "when instrumenting ['mock_gem']" do
      include_examples 'error tracking behavior', nil, ['mock_gem'], ['mock_gem client error', 'mock_gem utils error']
    end
  end

  describe 'use ErrorTracking component with combined user and module settings' do
    context "when tracking user code and instrumenting ['mock_gem/client']" do
      include_examples 'error tracking behavior',
        'user',
        ['mock_gem/client'],
        ['user code error', 'lib1 error', 'lib2 error', 'sublib1 error', 'sublib2 error', 'mock_gem client error']
    end
  end
end
