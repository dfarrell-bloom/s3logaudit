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
    it "should write queued strings to stdout" do
        wq = WorkQueue.new :threads => 5 do |str|
            puts str
        end
        100.times do |t|
            wq.enqueue "#{rand()*100}"
        end
        wq.exit_on_empty = true
        wq.run
        wq.joinThreads
    end
        
    test_data = []
    1000.times do 
        test_data << rand() * 100
    end
    test_proc = proc { |arr,i|
        arr[i] = arr[i] * 2
    }
    expected_results = test_data.dup
    expected_results.each_index { |i|
        test_proc.call expected_results, i
    }


end
