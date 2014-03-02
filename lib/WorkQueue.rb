
require 'thread'
require 'logger'

class WorkQueue

    def self.default_config 
        { 
            # every queue_wait_timeout seconds this @thread_exit will be checked
            # so threads don't just hang on the queue forever.
            # the lower the queue wait timeout, the 
            # sooner threds will end when @thread_exit is true
            # set to 0 if you want all threads to block on the queue forever.
            :queue_wait_timeout => 2, 
            :threads            => 10,
            :log_leel           => Logger::DEBUG,
            :log_destination    => $stderr,
        }
    end

    attr_accessor :thread_exit, :exit_on_empty
    attr_reader :config

    def self.default_queue_runner 
        Proc.new {
            until threadsShouldExit
                if @config[:queue_wait_timeout ]
                    begin 
                        queue_object = Timeout::timeout( @config[:queue_wait_timeout] ) { 
                            queue_object = @queue.pop
                        }
                    rescue Timeout::Error
                        next
                    end
                else # no :queue_wait_timeout, wait forever
                    queue_object = @queue.pop
                end
                log_debug "Thread #{Thread.current} got an object off the queue: #{queue_object}"
                @work_block.call queue_object
                log_debug "Thread #{Thread.current} finished processing: #{queue_object}"
            end
            log_debug "Thread #{Thread.current} queue running finished, exiting"
        }
    end

    def queue_runner_block
        self.class.default_queue_runner
    end
    
    def initialize config = nil, &blk
        configure config
        @queue_runner_block = queue_runner_block
        @queue = Queue.new
        @work_block = nil
        if block_given? 
            setWorkBlock blk
        end
        @threads = []
        @thread_exit = false # flag for threads to exit wait loop
        @exit_on_empty = false # flag for threads to exit wait loop when queue is empty ( eg filling is complete ) 
        
        @log_mutex = Mutex.new # don't overwrite our own logs
        if @config[:log_destination]
            @log = Logger.new @config[:log_destination]
            @log.level = @config[:log_level]
        else
            @log = nil
        end

    end

    def log_debug msg
        return unless @log
        @log_mutex.synchronize { @log.debug msg }
    end

    def log_info msg
        return unless @log
        @log_mutex.synchronize { @log.info msg }
    end

    def log_warn msg
        return unless @log
        @log_mutex.synchronize { @log.warn msg }
    end

    def configure config = nil
        @config = self.class.default_config unless @config
        return unless config
        unless config.kind_of? Hash
            raise TypeError.new "#{self.class.name}##{__method__} takes optional Hash argument, not #{config.class.name}" 
        end
        @config.merge! config 
    end

    # how is the work to be done?
    def setWorkBlock blk
        @work_block = blk
    end

    def enqueue obj
        @queue.push obj
    end

    def run &blk
        if block_given?
            setWorkBlock &blk
        end
        unless @work_block.kind_of? Proc
            raise WorkQueue::Error.new "call setWorkBlock before run so threads have something to do" 
        end
        spawnThreads
    end

    def threadsShouldExit 
        return true if @thread_exit 
        return true if @exit_on_empty and ( @queue.length <= s3ObjectQueue.num_waiting  )
        return false 
    end

    def spawnThreads 
        unless @threads.count == 0
            raise WorkQueue::Error.new "Threads already spawned"
        end
        @config[:threads].times do 
            @threads << Thread.new &@queue_runner_block
        end
    end

    def joinThreads 
        @threads.each do |th|
            th.join if th.alive?   
        end
        threads = @threads.dup
        @threads = [] 
        return threads
    end

    class Error < Exception
    end
end
