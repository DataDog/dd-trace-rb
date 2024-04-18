require 'datadog/profiling/collectors/info'
require 'json-schema'

RSpec.describe Datadog::Profiling::Collectors::Info do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:info) { info_collector.info }

  subject(:info_collector) { described_class.new(settings) }

  describe '#info' do
    it 'records useful info in multiple categories' do
      settings.service = 'test'
      expect(info).to match(
        {
          platform: hash_including(
            kernel_name: Datadog::Core::Environment::Platform.kernel_name,
          ),
          runtime: hash_including(
            engine: Datadog::Core::Environment::Identity.lang_engine,
          ),
          application: hash_including(
            service: settings.service,
          ),
          profiler: hash_including(
            version: Datadog::Core::Environment::Identity.gem_datadog_version,
          ),
        }
      )
    end

    it 'records a sensible application start time' do
      now = Time.now

      # We approximate the start time to the loading time of info. For this not to be
      # too flaky, we just check an approximate order of magnitude and parsing format.
      parsed_start_time = Time.iso8601(info[:application][:start_time])
      expect(parsed_start_time).to be_between(now - 60 * 60, now)
    end

    it 'records profiler info including a json dump of settings' do
      settings.profiling.advanced.max_frames = 600
      settings.profiling.advanced.experimental_heap_enabled = true

      expect(info[:profiler][:settings][:advanced]).to match(
        a_hash_including(
          max_frames: 600,
          experimental_heap_enabled: true,
        )
      )
    end

    it 'caches data' do
      expect(info_collector.info).to be(info_collector.info)
    end

    context 'with exotic-typed profile settings' do
      let(:settings) do
        TestSettings.new
      end

      it 'handles multiple types nicely' do
        expect(info[:profiler][:settings]).to match(
          {
            boolean_opt: true,
            symbol_opt: :a_symbol,
            string_opt: 'a string',
            integer_opt: 123,
            float_opt: 123.456,
            nil_opt: nil,
            advanced: {
              list_opt: [false, 1, 2.0, '3', nil, [1, 2, 3], { 'a' => 'a', 'b' => 'b' }, :a_symbol,
                         a_string_including('#<ComplexObject:')],
              hash_opt: {
                a: false,
                b: 1,
                c: 2.0,
                d: '3',
                e: nil,
                f: [1, 2, 3],
                g: { 'a' => 'a', 'b' => 'b' },
                h: :a_symbol,
                i: a_string_including('#<ComplexObject:')
              },
              proc_opt: a_string_including('#<Proc:'),
              complex_obj_opt: a_string_including('#<ComplexObject:')
            }
          }
        )
      end
    end
  end
end

class ComplexObject
  @some_field = 1
end

class TestSettings
  include Datadog::Core::Configuration::Base

  option :service do |o|
    o.default 'test-service'
  end

  option :env do |o|
    o.default 'test-env'
  end

  option :version do |o|
    o.default 'test-version'
  end

  settings :profiling do
    option :boolean_opt do |o|
      o.type :bool
      o.default true
    end

    option :symbol_opt do |o|
      o.type :symbol
      o.default :a_symbol
    end

    option :string_opt do |o|
      o.type :string
      o.default 'a string'
    end

    option :integer_opt do |o|
      o.type :int
      o.default 123
    end

    option :float_opt do |o|
      o.type :float
      o.default 123.456
    end

    option :nil_opt do |o|
    end

    settings :advanced do
      option :list_opt do |o|
        o.type :array
        o.default [false, 1, 2.0, '3', nil, [1, 2, 3], { 'a' => 'a', 'b' => 'b' }, :a_symbol, ComplexObject.new]
      end

      option :hash_opt do |o|
        o.type :hash
        o.default(
          {
            a: false,
            b: 1,
            c: 2.0,
            d: '3',
            e: nil,
            f: [1, 2, 3],
            g: { 'a' => 'a', 'b' => 'b' },
            h: :a_symbol,
            i: ComplexObject.new,
          }
        )
      end

      option :proc_opt do |o|
        o.type :proc
        o.default do
          proc {
            'proc result'
          }
        end
      end

      option :complex_obj_opt do |o|
        o.default ComplexObject.new
      end
    end
  end
end
