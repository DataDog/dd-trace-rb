module Lib2
  def self.rescue_error
    begin
      raise 'lib2 error'
    rescue
    end
  end
end
