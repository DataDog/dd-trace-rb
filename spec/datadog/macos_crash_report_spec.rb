require "spec_helper"

RSpec.describe MacosCrashReport do
  let(:report) { Tempfile.new(["ruby-crash", ".ips"]) }

  after do
    report.close
    report.unlink
  end

  def write_report(payload)
    report.write("#{JSON.dump("app_name" => "ruby")}\n#{JSON.dump(payload)}")
    report.flush

    allow(described_class).to receive(:paths).and_return([report.path])
  end

  describe ".find" do
    it "finds the report left behind by a child of this process" do
      write_report("pid" => 4242, "parentPid" => Process.pid)

      expect(described_class.find(4242)).to eq(report.path)
    end

    it "ignores the report of an unrelated process that had been assigned the same pid" do
      write_report("pid" => 4242, "parentPid" => Process.pid + 1)

      expect(described_class.find(4242)).to be nil
    end
  end

  describe ".describe" do
    it "summarizes the exception and the faulting thread, and appends the report as it came" do
      write_report(
        "exception" => {"type" => "EXC_BREAKPOINT"},
        "termination" => {"namespace" => "SIGNAL"},
        "asi" => {"libsystem_c.dylib" => ["crashed on child side of fork pre-exec"]},
        "os_fault" => {"process" => "ruby"},
        "faultingThread" => 1,
        "threads" => [
          {"frames" => [{"imageIndex" => 0, "symbol" => "not_the_faulting_thread", "symbolLocation" => 1}]},
          {"frames" => [{"imageIndex" => 0, "symbol" => "_pthread_mutex_corruption_abort", "symbolLocation" => 28}]},
        ],
        "usedImages" => [{"name" => "libsystem_pthread.dylib"}],
      )

      expect(described_class.describe(report.path)).to eq(
        <<~REPORT + File.read(report.path)
          macOS crash report #{report.path}:
            exception: {"type" => "EXC_BREAKPOINT"}
            termination: {"namespace" => "SIGNAL"}
            asi: {"libsystem_c.dylib" => ["crashed on child side of fork pre-exec"]}
            os_fault: {"process" => "ruby"}
            faulting thread 1:
               0 libsystem_pthread.dylib          _pthread_mutex_corruption_abort + 28
            raw report:
        REPORT
      )
    end

    it "says so when the report does not have the keys we expect, and still appends it" do
      write_report("pid" => 4242, "renamedException" => {"type" => "EXC_BREAKPOINT"})

      expect(described_class.describe(report.path)).to eq(
        <<~REPORT + File.read(report.path)
          macOS crash report #{report.path} is not in the expected format (no exception, termination, faultingThread, threads, usedImages, frames of the faulting thread):
            raw report:
        REPORT
      )
    end
  end

  describe ".newest_report_summary" do
    it "reports the top-level keys of the most recent report" do
      write_report("pid" => 4242, "parentPid" => Process.pid)

      expect(described_class.newest_report_summary).to eq(
        %(Newest crash report is #{report.path}, with top-level keys ["parentPid", "pid"])
      )
    end
  end
end
