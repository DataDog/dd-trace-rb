module Lib1
  def self.rescue_error
    begin
      raise 'lib1 error'
    rescue
      # do nothing
    end
  end
end
