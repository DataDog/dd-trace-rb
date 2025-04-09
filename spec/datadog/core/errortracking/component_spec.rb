require 'spec_helper'
require 'datadog/core/errortracking/component'

RSpec.describe Datadog::Core::Errortracking::Component, skip: !ErrortrackingHelpers.supported? do
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

    it 'simple begin rescue' do
      span = tracer.trace('operation') do |inner_span|
        begin
          raise 'this is an exception'
        rescue
        end
        inner_span.finish
      end
      expect(span.events.length).to eq(1)
      expect(span.events[0].attributes['type']).to eq('RuntimeError')
      expect(span.events[0].attributes['message']).to eq('this is an exception')
    end

    it 'multiple begin rescue' do
      span = tracer.trace('operation') do |inner_span|
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
      expect(span.events.length).to eq(2)

      expect(span.events[0].attributes['type']).to eq('RuntimeError')
      expect(span.events[0].attributes['message']).to eq('this is an exception')

      expect(span.events[1].attributes['type']).to eq('StandardError')
      expect(span.events[1].attributes['message']).to eq('this is another exception')
    end

    it 'nested begin rescue' do
      span = tracer.trace('operation') do |inner_span|
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
      expect(span.events.length).to eq(2)

      expect(span.events[0].attributes['type']).to eq('RuntimeError')
      expect(span.events[0].attributes['message']).to eq('this is an exception')

      expect(span.events[1].attributes['type']).to eq('RuntimeError')
      expect(span.events[1].attributes['message']).to eq('this is another exception')
    end

    it 'rescued then reraise then rescued' do
      span = tracer.trace('operation') do |inner_span|
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
      expect(span.events.length).to eq(1)

      expect(span.events[0].attributes['type']).to eq('RuntimeError')
      expect(span.events[0].attributes['message']).to eq('this is an exception')
    end

    it 'rescued then raise' do
      span_op = nil
      begin
        tracer.trace('operation') do |inner_span|
          # Store the span reference before raising the exception
          span_op = inner_span
          begin
            raise 'this is an exception'
          rescue StandardError => e
            raise e
          end
        end
      rescue
      end
      span = span_op.finish
      expect(span.events.length).to eq(0)
    end
  end

  shared_examples 'error tracking behavior' do |instrument_setting = nil, modules_to_instrument = [], expected_errors = []|
    before(:all) do
      require 'tmpdir'
      require 'fileutils'

      # Create a mock gem structure
      @gem_root = Dir.mktmpdir('mock_gem')
      @gem_lib_dir = File.join(@gem_root, 'gems/mock-gem-2.1.1/lib')
      FileUtils.mkdir_p(@gem_lib_dir)

      # Create a typical gem structure with nested directories
      FileUtils.mkdir_p(File.join(@gem_lib_dir, 'mock_gem'))

      # Create main file that users would require
      File.open(File.join(@gem_lib_dir, 'mock_gem.rb'), 'w') do |f|
        f.write <<-RUBY
          require 'mock_gem/client'
          require 'mock_gem/utils'

          module MockGem
            VERSION = '2.1.1'
          end
        RUBY
      end

      # Create client file in the gem
      File.open(File.join(@gem_lib_dir, 'mock_gem/client.rb'), 'w') do |f|
        f.write <<-RUBY
          module MockGem
            class Client
              def self.rescue_error
                begin
                  raise 'mock_gem client error'
                rescue => e
                  return e
                end
              end
            end
          end
        RUBY
      end

      # Create utils file in the gem
      File.open(File.join(@gem_lib_dir, 'mock_gem/utils.rb'), 'w') do |f|
        f.write <<-RUBY
          module MockGem
            module Utils
              def self.rescue_error
                begin
                  raise 'mock_gem utils error'
                rescue => e
                  return e
                end
              end
            end
          end
        RUBY
      end

      # Add gem path to load path
      $LOAD_PATH.unshift(@gem_lib_dir)
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
end
