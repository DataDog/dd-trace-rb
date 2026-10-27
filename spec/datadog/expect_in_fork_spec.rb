require "spec_helper"

RSpec.describe "SynchronizationHelpers#expect_in_fork" do
  it "works" do
    pid1 = Process.pid
    pid2 = nil
    expect_in_fork do
      pid2 = Process.pid
      expect(pid2).not_to eq(pid1)
    end
    expect(pid1).not_to eq(pid2)
  end

  it "errors for failing regular expectations" do
    expect {
      expect_in_fork do
        expect(1).to eq(2)
      end
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "errors for failing mock expectations" do
    expect {
      expect_in_fork do
        expect(Process).to receive(:pid)
        # Not calling Process.pid, should fail
      end
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  context "when the fork is killed by a signal on macOS" do
    before { allow(PlatformHelpers).to receive(:mac?).and_return(true) }

    it "reports the crash report macOS left behind" do
      allow(MacosCrashReport).to receive(:find).and_return("/fake/report.ips")
      allow(MacosCrashReport).to receive(:describe).with("/fake/report.ips").and_return("<crash report>")

      expect {
        expect_in_fork { Process.kill("KILL", Process.pid) }
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /<crash report>/)
    end

    it "reports what it did find when there is no crash report for the fork" do
      stub_const("SynchronizationHelpers::MACOS_CRASH_REPORT_TIMEOUT_SECONDS", 1)
      allow(MacosCrashReport).to receive(:find).and_return(nil)
      allow(MacosCrashReport).to receive(:newest_report_summary).and_return("<newest report>")

      expect {
        expect_in_fork { Process.kill("KILL", Process.pid) }
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Unable to collect .*\n<newest report>/)
    end

    # Otherwise we would wait on a crash report that is never coming, for every fork that fails an expectation
    it "does not look for a crash report when the fork was not killed" do
      expect(MacosCrashReport).to_not receive(:find)

      expect {
        expect_in_fork { expect(1).to eq(2) }
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
