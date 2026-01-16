# frozen_string_literal: true

require "datadog/profiling/spec_helper"

RSpec.describe "Datadog::Profiling::Ext::ExecMonkeyPatch" do
  let(:described_class) { Datadog::Profiling::Ext::ExecMonkeyPatch }

  subject! do
    skip("This monkey patch is not available on Ruby 2.6 or below") if RUBY_VERSION < "2.7"

    require "datadog/profiling/ext/exec_monkey_patch"

    described_class
  end

  before do
    # Validate there's no previous leaked state
    expect(Object.ancestors).to_not include(Datadog::Profiling::Ext::ExecMonkeyPatch::ObjectMonkeyPatch)
  end

  describe ".apply!" do
    it "prepends the Object monkey patch" do
      expect_in_fork do
        described_class.apply!

        expect(Object.ancestors).to include(Datadog::Profiling::Ext::ExecMonkeyPatch::ObjectMonkeyPatch)
      end
    end
  end

  describe "ObjectMonkeyPatch#exec" do
    it "shuts down the profiler before exec" do
      expect_in_fork do
        profiler = instance_double("Datadog::Profiling::Profiler", shutdown!: nil)
        components = instance_double("Datadog::Core::Components", profiler: profiler)
        allow(Datadog).to receive(:components).with(allow_initialization: false).and_return(components)

        described_class.apply!

        # Since the exec fails, our test continues to run, but we get to validate it was actually wrapped correctly
        expect { exec("this_does_not_exist_and_will_thus_fail") }.to raise_error(Errno::ENOENT)

        expect(profiler).to have_received(:shutdown!).with(report_last_profile: false)
      end
    end
  end
end
