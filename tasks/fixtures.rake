# frozen_string_literal: true

require_relative "lib/fixtures/ffe"

repo_root = File.expand_path("..", __dir__)

namespace :fixtures do
  namespace :ffe do
    desc "Download canonical FFE fixtures for the pinned upstream commit into tmp/ (network needed once per commit)"
    task :download do
      puts "FFE fixtures cached at #{FfeFixtures.download(repo_root)}"
    end
  end
end
