
require 'aws-sdk'
require_relative "lib/StatusMsg.rb"
require_relative "lib/WorkQueue.rb"

sm = StatusMsg.new

semaphore = Mutex.new 

s3 = AWS::S3.new
s3b = s3.buckets[ 'bgrady-etl-archive' ]
last_object = nil
last_object_modified = nil

wq = WorkQueue.new :threads=>1 do |obj|
    mod = obj.last_modified
    sm.log "Newest was #{last_object ? "#{last_object.key} modified #{last_object_modified}" : "not found yet" } | Examining #{obj.key} last modified #{mod}"
    semaphore.synchronize {
    if !last_object_modified or last_object_modified < mod
        last_object = obj 
        last_object_modified = mod
    end
    }
    next if obj.key =~ /^logs20/
    sm.show "Ojbect is not =~ /^logs20: #{obj.key}"
end
s3b.objects.each do |obj|
    wq.enqueue obj
end
wq.run
wq.joinThreads

puts "\nLast object is :#{last_object.key} modified #{last_object_modified}"
