# rubocop:disable Lint/AssignmentInCondition

module SerializerHelper
  def define_serialize_value_cases(cases)
    cases.each do |c|
      value = c.fetch(:input)
      var_name = c[:var_name]

      context c.fetch(:name) do
        let(:value) do
          if Proc === value
            value.call
          else
            value
          end
        end

        let(:options) do
          {name: var_name}
        end

        if expected_matches = c[:expected_matches]
          it "serialization matches expectation" do
            expect(serialized).to match(expected_matches)
          end
        else
          expected = c.fetch(:expected)
          it "serializes exactly as specified" do
            expect(serialized).to eq(expected)
          end
        end
      end
    end
  end

  def default_settings
    let(:settings) do
      double("settings").tap do |settings|
        allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
      end
    end

    let(:di_settings) do
      double("di settings").tap do |settings|
        # Reduce max capture depth to 2 from the default of 3.
        stub_di_settings(settings,
          max_capture_depth: 2,
          max_capture_attribute_count: 10,
          max_capture_collection_size: 10,
          redacted_type_names: %w[DISerializerSpecSensitiveType DISerializerSpecWildCard*],)
      end
    end
  end

  # Helper to save and restore the DI custom serializer registry to prevent test pollution.
  # Use this in contexts that register custom serializers with Datadog::DI::Serializer.register.
  #
  # Example:
  #   context 'when custom serializer is registered' do
  #     with_di_registry_change
  #
  #     before do
  #       Datadog::DI::Serializer.register(...) { ... }
  #     end
  #   end
  def with_di_registry_change
    around do |example|
      original_registry = Datadog::DI::Serializer.class_variable_get(:@@flat_registry).dup
      example.run
      Datadog::DI::Serializer.class_variable_set(:@@flat_registry, original_registry)
    end
  end

  # Stubs the thread CPU clock reads (`Process.clock_gettime` with
  # `CLOCK_THREAD_CPUTIME_ID`, `:float_second`) to return `values` in
  # order. Reads of other clocks and units pass through to the real
  # clock, so a probe's rate limiter construction, which reads the
  # monotonic clock, is unaffected.
  def stub_cpu_clock(values)
    before do
      original_clock_gettime = Process.method(:clock_gettime)
      calls = 0
      allow(Process).to receive(:clock_gettime) do |*args|
        if args.length == 2 && args[0] == Process::CLOCK_THREAD_CPUTIME_ID && args[1] == :float_second
          values[calls].tap { calls += 1 }
        else
          original_clock_gettime.call(*args)
        end
      end
    end
  end
end

# rubocop:enable Lint/AssignmentInCondition
