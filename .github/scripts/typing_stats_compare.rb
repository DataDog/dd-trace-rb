#!/usr/bin/env ruby

# frozen_string_literal: true

require "json"

head_stats = JSON.parse(File.read(ENV["CURRENT_STATS_PATH"]), symbolize_names: true)
base_stats = JSON.parse(File.read(ENV["BASE_STATS_PATH"]), symbolize_names: true)

# If a file is added in contrib, currently the paths will have no diff.
ignored_files = {
  added: head_stats[:ignored_files][:paths] - base_stats[:ignored_files][:paths],
  removed: base_stats[:ignored_files][:paths] - head_stats[:ignored_files][:paths]
}

def ignored_files_summary(head_stats, base_stats)
  # This will skip the summary if files are added/removed from contrib folders for now.
  ignored_files_added = head_stats[:ignored_files][:paths] - base_stats[:ignored_files][:paths]
  ignored_files_removed = base_stats[:ignored_files][:paths] - head_stats[:ignored_files][:paths]
  return nil if ignored_files_added.empty? && ignored_files_removed.empty?

  typed_files_percentage_base = ((base_stats[:total_files_size] - base_stats[:ignored_files][:size]) / base_stats[:total_files_size].to_f * 100).round(2)
  typed_files_percentage_head = ((head_stats[:total_files_size] - head_stats[:ignored_files][:size]) / head_stats[:total_files_size].to_f * 100).round(2)

  summary = +"This PR "
  summary << "adds **#{ignored_files_added.size}** ignored files " if ignored_files_added.any?
  summary << "and " if ignored_files_added.any? && ignored_files_removed.any?
  summary << "removes **#{ignored_files_removed.size}** ignored files " if ignored_files_removed.any?
  if typed_files_percentage_base != typed_files_percentage_head
    summary << "which #{(typed_files_percentage_base > typed_files_percentage_head) ? "decreases" : "increases"} the percentage of typed files from #{typed_files_percentage_base}% to #{typed_files_percentage_head}% (**#{(typed_files_percentage_head - typed_files_percentage_base).round(2)}**%)"
  end
  summary << "."

  <<~IGNORED_FILES
    ### Ignored files
    #{summary}
    <details><summary>Ignored files</summary>
      #{"<em>Added:</em>" if ignored_files_added.any?}
      #{"<pre><code>#{ignored_files_added.join("\n")}</code></pre>" if ignored_files_added.any?}
      #{"<em>Removed:</em>" if ignored_files_removed.any?}
      #{"<pre><code>#{ignored_files_removed.join("\n")}</code></pre>" if ignored_files_removed.any?}
    </details>

  IGNORED_FILES
end

result = +""
result << ignored_files_summary(head_stats, base_stats)
puts result
