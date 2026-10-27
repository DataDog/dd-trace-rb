require "json"

# macOS can kill a process with an uncatchable signal and no output of its own: the kernel does this when a system
# library hits a `brk` in the "hard trap" range, which is how libsystem flags disallowed operations such as the ones
# a forked child must avoid (see CAVEATS in `man 2 fork`). The only explanation ends up in the crash report that
# ReportCrash writes asynchronously.
module MacosCrashReport
  REPORTS_GLOB = "~/Library/Logs/DiagnosticReports/*.ips"

  # Keys `describe` reads; a report without them means the format changed under us
  EXPECTED_KEYS = %w[exception termination faultingThread threads usedImages].freeze

  module_function

  # These reports are kept around and macOS recycles pids, so we match on the parent pid too to reject reports left
  # behind by an unrelated process that happened to have the same pid
  def find(pid, parent_pid: Process.pid)
    paths.find do |path|
      report = payload(path)
      report["pid"] == pid && report["parentPid"] == parent_pid
    end
  end

  def describe(path)
    report = payload(path)
    frames = report.dig("threads", report["faultingThread"].to_i, "frames")

    unexpected = EXPECTED_KEYS - report.keys
    unexpected << "frames of the faulting thread" if frames.nil?

    summary = if unexpected.any?
      ["macOS crash report #{path} is not in the expected format (no #{unexpected.join(", ")}):"]
    else
      images = report["usedImages"]

      [
        "macOS crash report #{path}:",
        "  exception: #{report["exception"].inspect}",
        "  termination: #{report["termination"].inspect}",
        "  asi: #{report["asi"].inspect}",
        "  os_fault: #{report["os_fault"].inspect}",
        "  faulting thread #{report["faultingThread"]}:",
        *frames.first(30).each_with_index.map do |frame, i|
          location = frame["symbol"] ? "#{frame["symbol"]} + #{frame["symbolLocation"]}" : "0x#{frame["imageOffset"].to_s(16)}"
          format("    %2d %-32s %s", i, images.dig(frame["imageIndex"].to_i, "name"), location)
        end,
      ]
    end

    [*summary, "  raw report:", File.read(path)].join("\n")
  end

  # Finding no report at all is most likely a renamed `pid`/`parentPid`, so show what the keys look like now
  def newest_report_summary
    newest = paths.max_by { |path| File.mtime(path) }
    return "No crash reports in #{File.expand_path(File.dirname(REPORTS_GLOB))}" unless newest

    "Newest crash report is #{newest}, with top-level keys #{payload(newest).keys.sort.inspect}"
  end

  def paths
    Dir[File.expand_path(REPORTS_GLOB)]
  end

  # An .ips file is a single-line JSON header, followed by the JSON payload
  def payload(path)
    JSON.parse(File.read(path).split("\n", 2).last.to_s)
  rescue JSON::ParserError
    {}
  end
end
