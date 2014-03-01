
require 'aws-sdk'
require 'thread'

class StatusMsg 
    attr_reader :lastlen
    attr_reader :lastmsg

    @@mutex = Mutex.new

    def mutex_lock
        @@mutex.owned? or @@mutex.lock
    end

    def mutex_unlock
        @@mutex.owned? and @@mutex.unlock 
    end

    def initialize
        reset
        set_outputter do |msg|
            $stderr.print msg
        end
    end
    
    def set_outputter &blk
        mutex_lock
        @outputter = blk
        mutex_unlock
    end
    
    def log msg
        mutex_lock
	    clear if @lastlen > 0 
	    @outputter.call msg 
	    @lastlen = msg.length
	    @lastmsg = msg
        mutex_unlock
    end

    # show a message that isn't status with a newline
    def show msg
        mutex_lock
        buf = @lastmsg
        clear
        tmsg = msg.dup
        tmsg = "#{tmsg}\n" unless tmsg =~ /\n$/
        @outputter.call tmsg
        log buf
        mutex_unlock
    end

    def append msg
        mutex_lock
        @outputter.call msg
        @lastlen = @lastlen + msg.length
        @lastmsg = @lastmsg + msg
        mutex_unlock
    end

    def clear
        mutex_lock
        @outputter.call "\r%#{@lastlen}s\r" % ""
        reset
        mutex_unlock
    end
    def reset
        mutex_lock
        @lastlen = 0
        @lastmsg = ""
        mutex_unlock
    end

end

