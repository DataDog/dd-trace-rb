# This file is taken from Sidekiq 4.x to patch older version of Sidekiq,
# In order to make it easier for testing.
#
# https://github.com/sidekiq/sidekiq/blob/4.x/lib/sidekiq/testing.rb

module Sidekiq
  module Queues
    class << self
      def [](queue)
        jobs_by_queue[queue]
      end

      def push(queue, klass, job)
        jobs_by_queue[queue] << job
        jobs_by_worker[klass] << job
      end

      def jobs_by_queue
        @jobs_by_queue ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def jobs_by_worker
        @jobs_by_worker ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def delete_for(jid, queue, klass)
        jobs_by_queue[queue.to_s].delete_if { |job| job['jid'] == jid }
        jobs_by_worker[klass].delete_if { |job| job['jid'] == jid }
      end

      def clear_for(queue, klass)
        jobs_by_queue[queue].clear
        jobs_by_worker[klass].clear
      end

      def clear_all
        jobs_by_queue.clear
        jobs_by_worker.clear
      end
    end
  end

  module Worker
    module ClassMethods
      def queue
        sidekiq_options['queue']
      end

      def jobs
        Queues.jobs_by_worker[to_s]
      end

      def clear
        Queues.clear_for(queue, to_s)
      end

      def drain
        while jobs.any?
          next_job = jobs.first
          Queues.delete_for(next_job['jid'], next_job['queue'], to_s)
          process_job(next_job)
        end
      end

      def perform_one
        raise(EmptyQueueError, 'perform_one called with empty job queue') if jobs.empty?

        next_job = jobs.first
        Queues.delete_for(next_job['jid'], queue, to_s)
        process_job(next_job)
      end

      def process_job(job)
        worker = new
        worker.jid = job['jid']
        worker.bid = job['bid'] if worker.respond_to?(:bid=)
        Sidekiq::Testing.server_middleware.invoke(worker, job, job['queue']) do
          execute_job(worker, job['args'])
        end
      end

      def execute_job(worker, args)
        worker.perform(*args)
      end
    end

    class << self
      def jobs
        Queues.jobs_by_queue.values.flatten
      end

      def clear_all
        Queues.clear_all
      end

      def drain_all
        while jobs.any?
          worker_classes = jobs.map { |job| job['class'] }.uniq

          worker_classes.each do |worker_class|
            worker_class.constantize.drain
          end
        end
      end
    end
  end
end
