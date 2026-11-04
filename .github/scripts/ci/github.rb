# frozen_string_literal: true

require "json"
require "open3"

module CI
  class GitHub
    def get(path)
      request("GET", path)
    end

    def list(path, key: nil)
      separator = path.include?("?") ? "&" : "?"
      pages = command("--paginate", "--slurp", "#{path}#{separator}per_page=100")
      pages.flat_map { |page| key ? page.fetch(key) : page }
    end

    def request(method, path, body = nil)
      arguments = ["--method", method, path]
      arguments += ["--input", "-"] if body
      command(*arguments, input: body ? JSON.generate(body) : "")
    end

    private

    def command(*arguments, input: "")
      output, error, status = Open3.capture3("gh", "api", *arguments, stdin_data: input)
      raise "GitHub API request failed: #{error}" unless status.success?

      JSON.parse(output)
    end
  end
end
