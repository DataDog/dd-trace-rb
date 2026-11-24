require "datadog/profiling/collectors/info"
require "json-schema"

RSpec.describe Datadog::Profiling::Collectors::Info do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:info) { info_collector.info }

  subject(:info_collector) { described_class.new(settings) }

  describe "#info" do
    it "records useful info in multiple categories" do
      settings.service = "test"
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
        },
      )
    end

    it "records a sensible application start time" do
      now = Time.now

      # We approximate the start time to the loading time of info. For this not to be
      # too flaky, we just check an approximate order of magnitude and parsing format.
      parsed_start_time = Time.iso8601(info[:application][:start_time])
      expect(parsed_start_time).to be_between(now - 60 * 60, now)
    end

    it "records profiler info including a json dump of settings" do
      settings.profiling.advanced.max_frames = 600
      settings.profiling.advanced.experimental_heap_enabled = true

      expect(info[:profiler][:settings][:advanced]).to match(
        a_hash_including(
          max_frames: 600,
          experimental_heap_enabled: true,
        ),
      )
    end

    it "reports whether YJIT and ZJIT are enabled" do
      hide_const("RubyVM::YJIT")
      stub_const("RubyVM::ZJIT", double("RubyVM::ZJIT", enabled?: true))

      expect(info.fetch(:runtime)).to include(yjit_enabled: false, zjit_enabled: true)
    end

    context "when the Ruby VM has no JIT" do
      it "reports both JITs as disabled" do
        hide_const("RubyVM::YJIT")
        hide_const("RubyVM::ZJIT")

        expect(info.fetch(:runtime)).to include(yjit_enabled: false, zjit_enabled: false)
      end
    end

    context "with exotic-typed profile settings" do
      let(:settings) do
        TestSettings.new
      end

      it "handles multiple types nicely" do
        expect(info[:profiler][:settings]).to match(
          {
            boolean_opt: true,
            symbol_opt: :a_symbol,
            string_opt: "a string",
            integer_opt: 123,
            float_opt: 123.456,
            nil_opt: nil,
            advanced: {
              list_opt: [false, 1, 2.0, "3", nil, [1, 2, 3], {"a" => "a", "b" => "b"}, :a_symbol,
                a_string_including("#<ComplexObject:")],
              hash_opt: {
                a: false,
                b: 1,
                c: 2.0,
                d: "3",
                e: nil,
                f: [1, 2, 3],
                g: {"a" => "a", "b" => "b"},
                h: :a_symbol,
                i: a_string_including("#<ComplexObject:"),
              },
              proc_opt: a_string_including("#<Proc:"),
              complex_obj_opt: a_string_including("#<ComplexObject:"),
            },
          },
        )
      end
    end

    describe "libdatadog version reporting" do
      it "reports the libdatadog version, including platform" do
        libdatadog_gem = Gem.loaded_specs["libdatadog"]

        expect(info.dig(:profiler, :libdatadog)).to eq("#{libdatadog_gem.version}-#{libdatadog_gem.platform}")
      end

      context "when libdatadog is not available in loaded_specs" do
        it "reports the libdatadog version, with an unknown platform" do
          expect(Gem.loaded_specs).to receive(:[]).with("libdatadog").and_return(nil)
          allow(Gem.loaded_specs).to receive(:[]).and_call_original

          expect(info.dig(:profiler, :libdatadog)).to eq("#{Libdatadog::VERSION}-(unknown)")
        end
      end
    end

    describe "gc tuning reporting" do
      context "when no gc tuning env vars are set" do
        it "reports an empty hash" do
          expect(info.fetch(:runtime).fetch(:gc_tuning)).to eq({})
        end
      end

      context "when some gc tuning env vars are set" do
        with_env "RUBY_GC_HEAP_FREE_SLOTS" => "12345"

        it "reports the gc tuning env vars" do
          expect(info.fetch(:runtime).fetch(:gc_tuning)).to eq({
            RUBY_GC_HEAP_FREE_SLOTS: "12345",
          })
        end
      end
    end
  end

  describe "#info_json" do
    it "serializes the info" do
      expect(info_collector.info_json).to eq(JSON.generate(info_collector.info))
    end

    it "caches the serialized info" do
      expect(info_collector.info_json).to be(info_collector.info_json)
    end

    context "when a JIT gets enabled at runtime" do
      before do
        yjit = double("RubyVM::YJIT")
        allow(yjit).to receive(:enabled?).and_return(false, true, true)
        stub_const("RubyVM::YJIT", yjit)
        hide_const("RubyVM::ZJIT")
      end

      it "serializes the info again, and caches the new result" do
        yjit_disabled = info_collector.info_json
        yjit_enabled = info_collector.info_json

        expect(JSON.parse(yjit_disabled, symbolize_names: true).fetch(:runtime)).to include(yjit_enabled: false)
        expect(JSON.parse(yjit_enabled, symbolize_names: true).fetch(:runtime)).to include(yjit_enabled: true)

        expect(info_collector.info_json).to be(yjit_enabled)
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
    o.default "test-service"
  end

  option :env do |o|
    o.default "test-env"
  end

  option :version do |o|
    o.default "test-version"
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
      o.default "a string"
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
        o.default [false, 1, 2.0, "3", nil, [1, 2, 3], {"a" => "a", "b" => "b"}, :a_symbol, ComplexObject.new]
      end

      option :hash_opt do |o|
        o.type :hash
        o.default(
          {
            a: false,
            b: 1,
            c: 2.0,
            d: "3",
            e: nil,
            f: [1, 2, 3],
            g: {"a" => "a", "b" => "b"},
            h: :a_symbol,
            i: ComplexObject.new,
          },
        )
      end

      option :proc_opt do |o|
        o.type :proc
        o.default do
          proc {
            "proc result"
          }
        end
      end

      option :complex_obj_opt do |o|
        o.default ComplexObject.new
      end
    end
  end
end
