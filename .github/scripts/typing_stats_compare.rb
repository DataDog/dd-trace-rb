#!/usr/bin/env ruby

require 'json'

current_stats = JSON.parse(File.read(ENV['CURRENT_STATS_PATH']), symbolize_names: true)
base_stats = JSON.parse(File.read(ENV['BASE_STATS_PATH']), symbolize_names: true)

# If a file is added in contrib, currently the paths will have no diff.
ignored_files_paths_added = current_stats[:ignored_files][:paths] - base_stats[:ignored_files][:paths]
ignored_files_paths_removed = base_stats[:ignored_files][:paths] - current_stats[:ignored_files][:paths]

steep_ignores_added = current_stats[:steep_ignore_comments] - base_stats[:steep_ignore_comments]
steep_ignores_removed = base_stats[:steep_ignore_comments] - current_stats[:steep_ignore_comments]

untyped_methods_added = current_stats[:untyped_methods] - base_stats[:untyped_methods]
untyped_methods_removed = base_stats[:untyped_methods] - current_stats[:untyped_methods]

partially_typed_methods_added = current_stats[:partially_typed_methods] - base_stats[:partially_typed_methods]
partially_typed_methods_removed = base_stats[:partially_typed_methods] - current_stats[:partially_typed_methods]

untyped_others_added = current_stats[:untyped_others] - base_stats[:untyped_others]
untyped_others_removed = base_stats[:untyped_others] - current_stats[:untyped_others]

partially_typed_others_added = current_stats[:partially_typed_others] - base_stats[:partially_typed_others]
partially_typed_others_removed = base_stats[:partially_typed_others] - current_stats[:partially_typed_others]

diff_stats = {
  ignored_files: {
    added: ignored_files_paths_added,
    removed: ignored_files_paths_removed
  },
  steep_ignores: {
    added: steep_ignores_added,
    removed: steep_ignores_removed
  },
  methods: {
    untyped: {
      added: untyped_methods_added,
      removed: untyped_methods_removed
    },
    partially_typed: {
      added: partially_typed_methods_added,
      removed: partially_typed_methods_removed
    }
  },
  others: {
    untyped: {
      added: untyped_others_added,
      removed: untyped_others_removed
    },
    partially_typed: {
      added: partially_typed_others_added,
      removed: partially_typed_others_removed
    }
  }
}

puts diff_stats.to_json
