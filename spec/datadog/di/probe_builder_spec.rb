require "datadog/di/spec_helper"
require "datadog/di/probe_builder"

RSpec.describe Datadog::DI::ProbeBuilder do
  di_test

  describe ".build_from_remote_config" do
    let(:probe) do
      described_class.build_from_remote_config(rc_probe_spec)
    end

    context "typical line probe" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa.rb", "lines" => [4321]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => false,
         # Use a value different from our library default to ensure that
         # it is correctly processed.
         "capture" => {"maxReferenceDepth" => 33, 'maxFieldCount' => 34},
         # Use a value different from our library default to ensure that
         # it is correctly processed.
         "sampling" => {"snapshotsPerSecond" => 4500},
         "evaluateAt" => "EXIT"}
      end

      it "creates line probe with corresponding values" do
        expect(probe.id).to eq "3ecfd456-2d7c-4359-a51f-d4cc44141ffe"
        expect(probe.type).to eq :log
        expect(probe.file).to eq "aaa.rb"
        expect(probe.line_no).to eq 4321
        expect(probe.type_name).to be nil
        expect(probe.method_name).to be nil
        expect(probe.max_capture_depth).to eq 33
        expect(probe.max_capture_attribute_count).to eq 34
        expect(probe.rate_limit).to eq 4500

        expect(probe.line?).to be true
        expect(probe.method?).to be false
      end
    end

    context "minimum set of fields" do
      # This is a made up payload to test attribute defaulting.
      # In practice payloads like this should not be seen.
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "type" => "LOG_PROBE",
         "where" => {"sourceFile" => "aaa.rb", "lines" => [4321]},}
      end

      describe ".max_capture_depth" do
        it "is nil" do
          expect(probe.max_capture_depth).to be nil
        end
      end

      describe ".rate_limit" do
        it "is defaulted to 5000" do
          expect(probe.rate_limit).to eq 5000
        end
      end
    end

    context "when lines is an array of nil" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa.rb", "lines" => [nil]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => false,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      describe "construction" do
        it "fails with exception" do
          expect do
            probe
          end.to raise_error(ArgumentError, /neither method nor line probe/)
        end
      end
    end

    context "RC payload with capture snapshot" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa", "lines" => [2]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => true,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      it "capture_snapshot? is true" do
        expect(probe.capture_snapshot?).to be true
      end
    end

    context "RC payload without capture snapshot" do
      let(:rc_probe_spec) do
        {"id" => "3ecfd456-2d7c-4359-a51f-d4cc44141ffe",
         "version" => 0,
         "type" => "LOG_PROBE",
         "language" => "python",
         "where" => {"sourceFile" => "aaa", "lines" => [4]},
         "tags" => [],
         "template" => "In aaa, line 1",
         "segments" => [{"str" => "In aaa, line 1"}],
         "captureSnapshot" => false,
         "capture" => {"maxReferenceDepth" => 3},
         "sampling" => {"snapshotsPerSecond" => 5000},
         "evaluateAt" => "EXIT"}
      end

      it "capture_snapshot? is false" do
        expect(probe.capture_snapshot?).to be false
      end
    end

    context "empty input" do
      let(:rc_probe_spec) { {} }

      it "raises ArgumentError" do
        expect do
          probe
        end.to raise_error(ArgumentError, /Malformed remote configuration entry/)
      end
    end
  end
end
