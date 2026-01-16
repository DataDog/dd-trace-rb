#!/usr/bin/env ruby

# frozen_string_literal: true

require "json"

head_stats = JSON.parse(File.read(ENV["CURRENT_STATS_PATH"]), symbolize_names: true)
base_stats = JSON.parse(File.read(ENV["BASE_STATS_PATH"]), symbolize_names: true)

def format_for_code_block(data)
  data.map do |item|
    formatted_string = +"#{item[:path]}:#{item[:line]}"
    formatted_string << "\n└── #{item[:line_content]}" if item[:line_content]
    formatted_string
  end.join("\n")
end

def pluralize(word, suffix = "s")
  "#{word}#{suffix}"
end

def concord(word, count, suffix = "s")
  (count > 1) ? pluralize(word, suffix) : word
end

def create_intro(
  added:,
  removed:,
  data_name:,
  added_partially: [],
  removed_partially: [],
  data_name_partially: nil,
  base_percentage: nil,
  head_percentage: nil,
  percentage_data_name: nil
)
  intro = +"This PR "
  intro << "introduces " if added.any? || added_partially.any?
  intro << "**#{added.size}** #{concord(data_name, added.size)}" if added.any?
  intro << " and " if added.any? && added_partially.any?
  intro << "**#{added_partially.size}** #{concord(data_name_partially, added_partially.size)}" if added_partially.any?
  intro << ", and " if (added.any? || added_partially.any?) && (removed.any? || removed_partially.any?)
  intro << "clears " if removed.any? || removed_partially.any?
  intro << "**#{removed.size}** #{concord(data_name, removed.size)}" if removed.any?
  intro << " and " if removed.any? && removed_partially.any?
  intro << "**#{removed_partially.size}** #{concord(data_name_partially, removed_partially.size)}" if removed_partially.any?
  if base_percentage != head_percentage
    intro << ". It #{(base_percentage > head_percentage) ? "decreases" : "increases"} "
    intro << "the percentage of #{pluralize(percentage_data_name)} from #{base_percentage}% to #{head_percentage}% "
    intro << "(**#{"+" if head_percentage > base_percentage}#{(head_percentage - base_percentage).round(2)}**%)"
  end
  intro << "."
  intro
end

def create_summary(
  added:,
  removed:,
  data_name:,
  added_partially: [],
  removed_partially: [],
  data_name_partially: nil,
  base_percentage: nil,
  head_percentage: nil,
  percentage_data_name: nil
)
  return [nil, 0] if added.empty? && removed.empty? && added_partially.empty? && removed_partially.empty?

  intro = create_intro(
    added: added,
    removed: removed,
    data_name: data_name,
    added_partially: added_partially,
    removed_partially: removed_partially,
    data_name_partially: data_name_partially,
    base_percentage: base_percentage,
    head_percentage: head_percentage,
    percentage_data_name: percentage_data_name
  )

  summary = +"### #{pluralize(data_name).capitalize}\n"
  summary << "#{intro}\n"
  if added.any? || removed.any?
    summary << "<details><summary>#{pluralize(data_name).capitalize} (<strong>+#{added&.size || 0}-#{removed.size || 0}</strong>)</summary>\n"
    if added.any?
      summary << "  ❌ <em>Introduced:</em>\n"
      summary << "  <pre><code>#{format_for_code_block(added)}</code></pre>\n"
    end
    if removed.any?
      summary << "  ✅ <em>Cleared:</em>\n"
      summary << "  <pre><code>#{format_for_code_block(removed)}</code></pre>\n"
    end
    summary << "</details>\n"
  end
  if added_partially.any? || removed_partially.any?
    summary << "<details><summary>#{pluralize(data_name_partially).capitalize} (<strong>+#{added_partially.size || 0}-#{removed_partially.size || 0}</strong>)</summary>\n"
    if added_partially.any?
      summary << "  ❌ <em>Introduced:</em>\n"
      summary << "  <pre><code>#{format_for_code_block(added_partially)}</code></pre>\n"
    end
    if removed_partially.any?
      summary << "  ✅ <em>Cleared:</em>\n"
      summary << "  <pre><code>#{format_for_code_block(removed_partially)}</code></pre>\n"
    end
    summary << "</details>\n"
  end
  summary << "\n"
  total_introduced = (added&.size || 0) + (added_partially&.size || 0)
  [summary, total_introduced]
end

def ignored_files_summary(head_stats, base_stats)
  # This will skip the summary if files are added/removed from contrib folders for now.
  ignored_files_added = head_stats[:ignored_files] - base_stats[:ignored_files]
  ignored_files_removed = base_stats[:ignored_files] - head_stats[:ignored_files]

  return [nil, 0] if ignored_files_added.empty? && ignored_files_removed.empty?

  typed_files_percentage_base = ((base_stats[:total_files_size] - base_stats[:ignored_files].size) / base_stats[:total_files_size].to_f * 100).round(2)
  typed_files_percentage_head = ((head_stats[:total_files_size] - head_stats[:ignored_files].size) / head_stats[:total_files_size].to_f * 100).round(2)

  intro = create_intro(
    added: ignored_files_added,
    removed: ignored_files_removed,
    data_name: "ignored file",
    base_percentage: typed_files_percentage_base,
    head_percentage: typed_files_percentage_head,
    percentage_data_name: "typed file"
  )

  summary = +"### Ignored files\n"
  summary << "#{intro}\n"
  summary << "<details><summary>Ignored files (<strong>+#{ignored_files_added&.size || 0}-#{ignored_files_removed&.size || 0}</strong>)</summary>\n"
  if ignored_files_added.any?
    summary << "  ❌ <em>Introduced:</em>\n"
    summary << "  <pre><code>#{ignored_files_added.join("\n")}</code></pre>\n"
  end
  if ignored_files_removed.any?
    summary << "  ✅ <em>Cleared:</em>\n"
    summary << "  <pre><code>#{ignored_files_removed.join("\n")}</code></pre>\n"
  end
  summary << "</details>\n"
  summary << "\n"
  total_introduced = ignored_files_added&.size || 0
  [summary, total_introduced]
end

def steep_ignore_summary(head_stats, base_stats)
  steep_ignore_added = head_stats[:steep_ignore_comments] - base_stats[:steep_ignore_comments]
  steep_ignore_removed = base_stats[:steep_ignore_comments] - head_stats[:steep_ignore_comments]

  create_summary(
    added: steep_ignore_added,
    removed: steep_ignore_removed,
    data_name: "<code>steep:ignore</code> comment"
  )
end

def untyped_methods_summary(head_stats, base_stats)
  untyped_methods_added = head_stats[:untyped_methods] - base_stats[:untyped_methods]
  untyped_methods_removed = base_stats[:untyped_methods] - head_stats[:untyped_methods]
  partially_typed_methods_added = head_stats[:partially_typed_methods] - base_stats[:partially_typed_methods]
  partially_typed_methods_removed = base_stats[:partially_typed_methods] - head_stats[:partially_typed_methods]
  total_methods_base = base_stats[:typed_methods_size] + base_stats[:untyped_methods].size + base_stats[:partially_typed_methods].size
  total_methods_head = head_stats[:typed_methods_size] + head_stats[:untyped_methods].size + head_stats[:partially_typed_methods].size
  typed_methods_percentage_base = (base_stats[:typed_methods_size] / total_methods_base.to_f * 100).round(2)
  typed_methods_percentage_head = (head_stats[:typed_methods_size] / total_methods_head.to_f * 100).round(2)

  create_summary(
    added: untyped_methods_added,
    removed: untyped_methods_removed,
    data_name: "untyped method",
    added_partially: partially_typed_methods_added,
    removed_partially: partially_typed_methods_removed,
    data_name_partially: "partially typed method",
    base_percentage: typed_methods_percentage_base,
    head_percentage: typed_methods_percentage_head,
    percentage_data_name: "typed method"
  )
end

def untyped_others_summary(head_stats, base_stats)
  untyped_others_added = head_stats[:untyped_others] - base_stats[:untyped_others]
  untyped_others_removed = base_stats[:untyped_others] - head_stats[:untyped_others]
  partially_typed_others_added = head_stats[:partially_typed_others] - base_stats[:partially_typed_others]
  partially_typed_others_removed = base_stats[:partially_typed_others] - head_stats[:partially_typed_others]
  total_others_base = base_stats[:typed_others_size] + base_stats[:untyped_others].size + base_stats[:partially_typed_others].size
  total_others_head = head_stats[:typed_others_size] + head_stats[:untyped_others].size + head_stats[:partially_typed_others].size
  typed_others_percentage_base = (base_stats[:typed_others_size] / total_others_base.to_f * 100).round(2)
  typed_others_percentage_head = (head_stats[:typed_others_size] / total_others_head.to_f * 100).round(2)

  create_summary(
    added: untyped_others_added,
    removed: untyped_others_removed,
    data_name: "untyped other declaration",
    added_partially: partially_typed_others_added,
    removed_partially: partially_typed_others_removed,
    data_name_partially: "partially typed other declaration",
    base_percentage: typed_others_percentage_base,
    head_percentage: typed_others_percentage_head,
    percentage_data_name: "typed other declaration"
  )
end

# Later we will make the CI fail if there's a regression in the typing stats
ignored_files_summary, _ignored_files_added = ignored_files_summary(head_stats, base_stats)
steep_ignore_summary, _steep_ignore_added = steep_ignore_summary(head_stats, base_stats)
untyped_methods_summary, untyped_methods_added = untyped_methods_summary(head_stats, base_stats)
untyped_others_summary, untyped_others_added = untyped_others_summary(head_stats, base_stats)
result = +""
result << ignored_files_summary if ignored_files_summary
if steep_ignore_summary || untyped_methods_summary || untyped_others_summary
  result << "*__Note__: Ignored files are excluded from the next sections.*\n\n"
end
result << steep_ignore_summary if steep_ignore_summary
result << untyped_methods_summary if untyped_methods_summary
result << untyped_others_summary if untyped_others_summary
if untyped_methods_added > 0 || untyped_others_added > 0
  result << "*If you believe a method or an attribute is rightfully untyped or partially typed, you can add `# untyped:accept` on the line before the definition to remove it from the stats.*\n"
end
print result
