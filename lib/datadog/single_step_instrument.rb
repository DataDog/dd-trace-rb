# frozen_string_literal: true

#
# Entrypoint file for single step instrumentation.
#
# This file's path is private. Do not reference this file.
#
begin
  require_relative 'auto_instrument'
rescue StandardError, LoadError => e
  warn "Single step instrumentation failed: #{e.class}:#{e.message}\n\tSource:\n\t#{Array(e.backtrace).join("\n\t")}"
end
