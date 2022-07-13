class BasicJob
  include Sidekiq::Job

  def perform(*args)
    puts "Received args #{args}"
    Test.all
    sleep 8
    puts "Job #{Time.now}"
  end
end
