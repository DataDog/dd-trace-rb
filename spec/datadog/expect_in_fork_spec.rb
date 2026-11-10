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

  # Runs expect_in_fork with a fork that reports its pid through a pipe.
  # Returns the fork's pid and the error expect_in_fork raised, if any.
  def run_reporting_fork_pid(**expect_in_fork_options, &fork_block)
    reader, writer = IO.pipe
    error = nil
    begin
      expect_in_fork(**expect_in_fork_options) do
        reader.close
        writer.puts(Process.pid)
        writer.close
        fork_block.call
      end
    rescue => e
      error = e
    end
    writer.close
    [Integer(reader.read), error]
  ensure
    reader.close
    writer.close unless writer.closed?
  end

  context "when the fork exits" do
    it "reaps the fork and does not signal it" do
      expect(Process).not_to receive(:kill)

      fork_pid, error = run_reporting_fork_pid {}

      expect(error).to be_nil
      expect { Process.wait(fork_pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
    end
  end

  context "when the fork does not exit within the timeout" do
    it "kills and reaps the fork" do
      expect(Process).to receive(:kill).with("KILL", Integer).and_call_original

      fork_pid, error = run_reporting_fork_pid(timeout_seconds: 1) do
        blocker_reader, _blocker_writer = IO.pipe
        # Blocks until killed: this process holds the write end open.
        blocker_reader.read
      end

      expect(error).to be_a(RuntimeError)
      expect(error.message).to start_with("Failure or timeout in `expect_in_fork`")
      expect { Process.wait(fork_pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
    end
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
