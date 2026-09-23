class MinimalExamples
  def initialize
    @selected_files = {}
  end

  def run(example)
    file_path = example.metadata.fetch(:absolute_file_path)

    if @selected_files[file_path]
      example.skip
    else
      @selected_files[file_path] = true
      example.run
    end
  end
end
