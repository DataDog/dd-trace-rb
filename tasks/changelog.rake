# frozen_string_literal: true

require_relative "release_prep/changelog"

namespace :changelog do
  task :format do
    ReleasePrep::Changelog.new.format
  end
end
