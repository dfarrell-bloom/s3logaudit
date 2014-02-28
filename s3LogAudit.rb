#!/usr/bin/env ruby

require 'thread'

require 'rubygems'
require 'aws-sdk'
require 'colorize'

config = { :object_threads => 5, :queue_timeout => 1 }

log = Logger.new $stderr
log.level = Logger::DEBUG

buckets=[]
begin
    ENV['AWS_LOG_BUCKETS'].split(' ').each do |bucket|
        buckets << bucket
    end
rescue NoMethodError
    buckets=[]
end

unless buckets.length > 0
    $stderr.puts "Please provide environment variable AWS_LOG_BUCKETS defining log buckets"
    exit 127
end

s3ObjectQueue = Queue.new
s3ObjectRunners = Array.new
filling = true

config[:object_threads].times do 
    th = Thread.new do 
        while filling || ( s3ObjectQueue.length > s3ObjectQueue.num_waiting  )
            begin 
                # timeout avoids race on filling set to false after thread begins waiting
                object = Timeout::timeout( config[:queue_timeout] ) { 
                    object = s3ObjectQueue.pop 
                }
            rescue Timeout::Error
                next # try again
            end
            Thread.exclusive {
                log.info "Examining object #{object.key.to_s.red} #{object.content_length} bytes, modified #{object.last_modified}"
            }       
        end
    end
    s3ObjectRunners.push th 
end

s3 = AWS::S3.new
buckets.each do |bucket|
    s3bucket = s3.buckets[bucket]
    unless s3bucket.exists?
        log.warn "Bucket #{bucket} does not exist."
        next
    end
    s3bucket.objects.each do |object|
        s3ObjectQueue.push object   
        Thread.exclusive { log.debug object.key.yellow }
    end
end

filling = false

s3ObjectRunners.each do |thread|
    thread.join if thread.alive? 
end

