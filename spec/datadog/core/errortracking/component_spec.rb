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

  shared_examples 'error tracking behavior' do |instrument_setting|
    before(:all) do
      require 'tmpdir'
      require 'fileutils'

      @gem_dir = Dir.mktmpdir('test')
      @gem_lib_dir = File.join(@gem_dir, 'gems/my-fake-gem-2.12.2/lib')
      FileUtils.mkdir_p(@gem_lib_dir)

      fake_gem_file = File.join(@gem_lib_dir, 'rescuer.rb')
      File.open(fake_gem_file, 'w') do |f|
        f.write <<~RUBY
          module FakeGem
            class ErrorRaiser
              def self.raise_error
                begin
                  raise StandardError, "gem error"
                rescue
                end
              end
            end
          end
        RUBY
      end
      $LOAD_PATH.unshift(@gem_lib_dir)

      # Only require the file if the module hasn't been defined yet
      require 'rescuer' unless defined?(FakeGem)
    end

    after(:all) do
      $LOAD_PATH.delete(@gem_lib_dir)
      FileUtils.remove_entry(@gem_dir) if @gem_dir && Dir.exist?(@gem_dir)
    end

    before do
      settings.errortracking.to_instrument = instrument_setting
      @errortracker = described_class.build(settings, tracer)
      tracer.enabled = true

      allow(Gem::Specification).to receive(:find_by_name).with('my-fake-gem').and_return(true)
    end

    after do
      @errortracker.stop
      tracer.shutdown!
    end

    it "tracks errors according to '#{instrument_setting}' setting" do
      span = tracer.trace('operation') do |inner_span|
        FakeGem::ErrorRaiser.raise_error
        begin
          raise 'user code error'
        rescue
        end
        inner_span.finish
      end

      expected_events = instrument_setting == 'all' ? 2 : 1
      expect(span.events.length).to eq(expected_events)
      if instrument_setting == 'user'
        expect(span.events[0].attributes['type']).to eq('RuntimeError')
        expect(span.events[0].attributes['message']).to eq('user code error')
      elsif instrument_setting == 'third_party'
        expect(span.events[0].attributes['type']).to eq('StandardError')
        expect(span.events[0].attributes['message']).to eq('gem error')
      else
        expect(span.events[0].attributes['type']).to eq('StandardError')
        expect(span.events[0].attributes['message']).to eq('gem error')

        expect(span.events[1].attributes['type']).to eq('RuntimeError')
        expect(span.events[1].attributes['message']).to eq('user code error')
      end
    end
  end

  describe 'use errortracking component with different settings' do
    context 'when tracking user code only' do
      include_examples 'error tracking behavior', 'user'
    end

    context 'when tracking third_party code' do
      include_examples 'error tracking behavior', 'third_party'
    end

    context 'when tracking all code' do
      include_examples 'error tracking behavior', 'all'
    end
  end

  describe 'use errortracking component with module-specific settings' do
    shared_examples 'module-specific error tracking' do |modules_to_instrument, expected_errors|
      context "when instrumenting #{modules_to_instrument}" do
        before do
          settings.errortracking.to_instrument_modules = modules_to_instrument
          @errortracker = described_class.build(settings, tracer)
          tracer.enabled = true

          require_relative './lib1'
          require_relative './lib2'
          require_relative './sublib/sublib1'
          require_relative './sublib/sublib2'
        end

        after do
          tracer.shutdown!
          @errortracker.stop
        end

        it 'tracks errors only from instrumented files' do
          span = tracer.trace('operation') do |inner_span|
            Lib1.rescue_error
            Lib2.rescue_error
            SubLib1.rescue_error
            SubLib2.rescue_error
            begin
              raise 'this is an error'
            rescue
            end
            inner_span.finish
          end

          expect(span.events.length).to eq(expected_errors.length)
          event_messages = span.events.map { |e| e.attributes['message'] }
          expected_errors.each do |error|
            expect(event_messages).to include(error)
          end
        end
      end
    end

    include_examples 'module-specific error tracking', ['lib1'], ['lib1 error']
    include_examples 'module-specific error tracking', ['sublib'], ['sublib1 error', 'sublib2 error']
    include_examples 'module-specific error tracking', ['sublib1', 'lib1'], ['sublib1 error', 'lib1 error']
    include_examples 'module-specific error tracking', ['sublib', 'lib1'], ['lib1 error', 'sublib1 error', 'sublib2 error']
  end
end
