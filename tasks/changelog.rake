# frozen_string_literal: true

require_relative "lib/release_prep"

namespace :changelog do
  task :format do
    ReleasePrep::Changelog.new.format
  end
end
