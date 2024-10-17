require "datadog/di/spec_helper"
require "datadog/di/code_tracker"

RSpec.describe Datadog::DI::CodeTracker do
  di_test

  let(:tracker) do
    described_class.new
  end

  describe "#start" do
    after do
      tracker.stop
    end

    it "tracks loaded file" do
      # The expectations appear to be lazy-loaded, therefore
      # we need to invoke the same expectation before starting
      # code tracking as we'll be using later in the test.
      expect(tracker.send(:registry)).to be_empty
      tracker.start
      # Should still be empty here.
      expect(tracker.send(:registry)).to be_empty
      load File.join(File.dirname(__FILE__), "code_tracker_load_class.rb")
      expect(tracker.send(:registry).length).to eq(1)

      path = tracker.send(:registry).to_a.dig(0, 0)
      # The path in the registry should be absolute.
      expect(path[0]).to eq "/"
      # The full path is dependent on the environment/system
      # running the tests, but we can assert on the basename
      # which will be the same.
      expect(File.basename(path)).to eq("code_tracker_load_class.rb")
      # And, we should in fact have a full path.
      expect(path).to start_with("/")
    end

    it "tracks required file" do
      # The expectations appear to be lazy-loaded, therefore
      # we need to invoke the same expectation before starting
      # code tracking as we'll be using later in the test.
      expect(tracker.send(:registry)).to be_empty
      tracker.start
      # Should still be empty here.
      expect(tracker.send(:registry)).to be_empty
      require_relative "code_tracker_require_class"
      expect(tracker.send(:registry).length).to eq(1)

      path = tracker.send(:registry).to_a.dig(0, 0)
      # The path in the registry should be absolute.
      expect(path[0]).to eq "/"
      # The full path is dependent on the environment/system
      # running the tests, but we can assert on the basename
      # which will be the same.
      expect(File.basename(path)).to eq("code_tracker_require_class.rb")
      # And, we should in fact have a full path.
      expect(path).to start_with("/")
    end

    context "eval without location" do
      it "does not track eval'd code" do
        # The expectations appear to be lazy-loaded, therefore
        # we need to invoke the same expectation before starting
        # code tracking as we'll be using later in the test.
        expect(tracker.send(:registry)).to be_empty
        tracker.start
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
        eval "1 + 2" # standard:disable Style/EvalWithLocation
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
      end
    end

    context "eval with location" do
      it "does not track eval'd code" do
        # The expectations appear to be lazy-loaded, therefore
        # we need to invoke the same expectation before starting
        # code tracking as we'll be using later in the test.
        expect(tracker.send(:registry)).to be_empty
        tracker.start
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
        eval "1 + 2", nil, __FILE__, __LINE__
        # Should still be empty here.
        expect(tracker.send(:registry)).to be_empty
      end
    end
  end

  describe "#active?" do
    context "when started" do
      before do
        tracker.start
      end

      after do
        tracker.stop
      end

      it "is true" do
        expect(tracker.active?).to be true
      end
    end

    context "when stopped" do
      before do
        tracker.start
        tracker.stop
      end

      it "is false" do
        expect(tracker.active?).to be false
      end
    end
  end

  describe "#iseqs_for_path_suffix" do
    around do |example|
      tracker.start

      load File.join(File.dirname(__FILE__), "code_tracker_test_class_1.rb")
      load File.join(File.dirname(__FILE__), "code_tracker_test_class_2.rb")
      load File.join(File.dirname(__FILE__), "code_tracker_test_class_3.rb")
      load File.join(File.dirname(__FILE__), "code_tracker_test_classes", "code_tracker_test_class_1.rb")
      expect(tracker.send(:registry).each.to_a.length).to eq(4)

      # To be able to assert on the registry, replace values (iseqs)
      # with the keys.
      (registry = tracker.send(:registry)).each do |k, v|
        registry[k] = k
      end

      example.run

      tracker.stop
    end

    context "exact match for full path" do
      let(:path) do
        File.join(File.dirname(__FILE__), "code_tracker_test_class_1.rb")
      end

      it "returns the exact match only" do
        expect(tracker.iseqs_for_path_suffix(path)).to eq([path])
      end
    end

    context "basename match" do
      let(:expected) do
        [
          File.join(File.dirname(__FILE__), "code_tracker_test_class_1.rb"),
          File.join(File.dirname(__FILE__), "code_tracker_test_classes", "code_tracker_test_class_1.rb"),
        ]
      end

      it "returns the exact match only" do
        expect(tracker.iseqs_for_path_suffix("code_tracker_test_class_1.rb")).to eq(expected)
      end
    end

    context "match not on path component boundary" do
      it "returns no matches" do
        expect(tracker.iseqs_for_path_suffix("1.rb")).to eq([])
      end
    end
  end
end
