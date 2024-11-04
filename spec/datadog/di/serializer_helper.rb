module SerializerHelper
  def define_serialize_value_cases(cases)
    cases.each do |c|
      value = c.fetch(:input)
      expected = c.fetch(:expected)
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

        it "serializes as expected" do
          expect(serialized).to eq(expected)
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
        allow(settings).to receive(:enabled).and_return(true)
        allow(settings).to receive(:propagate_all_exceptions).and_return(false)
        allow(settings).to receive(:redacted_identifiers).and_return([])
        allow(settings).to receive(:redacted_type_names).and_return(%w[
          DISerializerSpecSensitiveType DISerializerSpecWildCard*
        ])
        allow(settings).to receive(:max_capture_collection_size).and_return(10)
        allow(settings).to receive(:max_capture_attribute_count).and_return(10)
        # Reduce max capture depth to 2 from default of 3
        allow(settings).to receive(:max_capture_depth).and_return(2)
        allow(settings).to receive(:max_capture_string_length).and_return(100)
      end
    end
  end
end
