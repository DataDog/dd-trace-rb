# frozen_string_literal: true

module Datadog
  module Core
    # Datadog::Core::DDSketch is defined completely in the native extension.
    # Do not define it here (for example, as an empty class) because we don't
    # want to be able to create instances of the empty stub class if the
    # native extension is missing or failed to load.
    #
    # Use Core.ddsketch_supported? to determine if DDSketch class exists and
    # is usable.
    #
    # See https://github.com/datadog/dd-trace-rb/pull/5008 and
    # https://github.com/DataDog/dd-trace-rb/pull/4901 for the background on
    # dependency issues with DDSketch.
  end
end
