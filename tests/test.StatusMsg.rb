
require_relative "../lib/StatusMsg.rb"

describe StatusMsg do
    sm = nil
    output = ""
    msgs = [ 
        "A very loooooooong message you should never seeeeeeeee ! ",
        "A shorter message"
    ]
    100.times do 
        msgs.push "A random string #{`openssl rand -hex #{rand 100}`.strip}"
    end
    expected_output = ""
    msgs.each do |msg|
        expected_output << msg
        expected_output << "\r%#{msg.length}s\r" % ""
    end
    outputter = proc { |msg|
       output << msg
    }
    it "should initialize cleanly" do
        sm = StatusMsg.new
    end
    it "should output messages to stdout out of the box" do
        msgs.each do |msg|
            sm.log msg
            sm.lastlen.should == msg.length
        end
    end
    it "should allow setting a different outputter" do
        sm.set_outputter &outputter
    end
    it "should reset" do
        sm.reset
    end
    it "should output with \\r properly" do 
        msgs.each do |msg|
            sm.log msg
        end
        sm.clear
        output.should == expected_output
    end
    it "should be thread safe ( each message should be written out in its entirety )" do
        sm.reset
        output = ""
        threads = []
        msgs.each do |msg|
            threads << Thread.new { sleep( rand()/100 ); sm.log msg }
        end
        threads.each { |th| th.join }
        sm.clear
        msgs.each do |msg|
            output.include?( msg ).should == true
        end
    end
    it "should append properly" do
        sm.reset
        output = ""
        sm.log msg1= "A message .... "
        sm.append msg2="continues"
        sm.log msg3 = "A new message"
        output.should == "#{msg1}#{msg2}\r%#{msg1.length + msg2.length}s\r#{msg3}" % [ "", "" ]
    end
    it "should show a message properly and then show the last logged message again" do
        sm.reset
        output = ""
        sm.log msg1= "A message .... "
        sm.append msg2="continues"
        sm.show msg3 = "A new message"
        output.should == "#{msg1}#{msg2}\r%#{msg1.length + msg2.length}s\r#{msg3}\n#{msg1}#{msg2}" % [ "", "" ]
    end

end
