require_relative "../lib/WorkQueue.rb"

describe WorkQueue do
    # initialization and configuration 
    it "should initialize cleanly with no options" do
        wq = WorkQueue.new 
        wq.config.should be_kind_of Hash
    end
    it "should raise error if initialized with a non-hash config" do
        expect { 
            WorkQueue.new "not a valid configuration arg!"
        }.to raise_exception TypeError
    end
    it "should intitalize cleanly with valid config passed" do
        wq = WorkQueue.new :queue_wait_timeout => 4, :threads => 100
        wq.config.should be_kind_of Hash
        wq.config[:queue_wait_timeout].should == 4
        wq.config[:threads].should == 100
    end
    it "should initialize cleanly with a work block" do
        WorkQueue.new do 
            puts "I Am a work block"
        end
    end
    it "should initialize cleanly with a config and work block" do
        wq = WorkQueue.new :threads => 5 do |str|
            puts str
        end
    end
    it "should write queued strings to stdout" do # simple example
        wq = WorkQueue.new :threads => 3 do |str|
            sleep( time = rand() / 10 )
            msg = "#{Thread.current} (after #{time} seconds): #{str}"
            Thread.exclusive { puts msg }
        end 
        # get the threads ready to run
        wq.run
        # enqueue some stuff
        10.times do |t|
            wq.enqueue "#{rand()*100}"
        end
        wq.exit_on_empty = true
        wq.joinThreads.each do |t|
            t.should be_kind_of Thread
            t.alive?().should == false
        end 
        wq.threadCount.should == 0  
        
    end
        
    test_data = []
    100000.times do 
        test_data << rand() * 100
    end
    test_proc = proc { |arr,i|
        arr[i] = arr[i] * 2
    }
    expected_results = test_data.dup
    expected_results.each_index { |i|
        test_proc.call expected_results, i
    }
    it "should accurately process the test array with the same results as done single-threaded" do
        wq = WorkQueue.new :log_destination => nil, :thread_wait_timeout => 0.1, :threads => 500,  &(test_proc.curry[test_data])
        wq.run
        test_data.each_index { |i| 
            wq.enqueue i 
        }
        wq.joinThreads 
        test_data.should == expected_results
    end

end
