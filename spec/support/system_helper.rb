module SystemHelper
  module_function

  # Returns a list of all open file descriptors held by this process.
  def open_fds
    # Unix-specific way to get the current process' open file descriptors and the files (if any) they correspond to
    Dir['/dev/fd/*'].each_with_object({}) do |fd, hash|
      hash[fd] =
        begin
          File.realpath(fd)
        rescue SystemCallError # This can fail due to... reasons, and we only want it for debugging so let's ignore
          nil
        end
    end.values
  end
end
