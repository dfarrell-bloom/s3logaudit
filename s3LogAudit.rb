#!/usr/bin/env ruby

require 'thread'
require 'json'

require 'rubygems'
require 'aws-sdk'
require 'colorize'
require 'mysql2'

require_relative "lib/S3BucketLog.rb"

config = { :object_threads => 40, :queue_timeout => 1 }

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

begin 
    masterconn = Mysql2::Client.new( 
        :host => ENV['MYSQL_HOST'], 
        :username=> ENV['MYSQL_USER'], 
        :password=> ENV['MYSQL_PASSWORD'],
        :database => ENV['MYSQL_DATABASE']
    )
    masterconn.query "CREATE TABLE IF NOT EXISTS log_entries ( 
        request_id CHAR(16) CHARACTER SET ascii NOT NULL,
        PRIMARY KEY(request_id),
        operation VARCHAR(255), 
        KEY( operation ), 
        owner VARCHAR(255) NOT NULL, 
        bucket VARCHAR(255) NOT NULL, 
        KEY( bucket ),
        `time` DATETIME NOT NULL,
        ip INT, 
        requester VARCHAR(255),
        KEY( requester ),
        `key` VARCHAR(1024) CHARACTER SET utf8,
        uri VARCHAR(2048) CHARACTER SET utf8,
        status SMALLINT UNSIGNED, 
        error VARCHAR(255) CHARACTER SET utf8,
        bytes_sent BIGINT UNSIGNED,
        object_size BIGINT UNSIGNED,
        total_ms BIGINT UNSIGNED,
        turnaround_ms BIGINT UNSIGNED,
        referrer VARCHAR(65535) CHARACTER SET utf8,
        user_agent VARCHAR(1024) CHARACTER SET utf8,
        version_id VARCHAR(255) CHARACTER SET utf8
    )"
rescue Mysql2::Error => e
    log.fatal "Mysql Error ##{e.errno} creating table `log_entries`: #{e.error}"
ensure
    masterconn.close if masterconn
end 

s3ObjectQueue = Queue.new
s3ObjectRunners = Array.new
filling = true

s3ls = S3LogSet.new

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
            myconn = Mysql2::Client.new( 
                :host => ENV['MYSQL_HOST'], 
                :username=> ENV['MYSQL_USER'], 
                :password=> ENV['MYSQL_PASSWORD'],
                :database => ENV['MYSQL_DATABASE']
            )
            # msg = "Examining object #{object.key.to_s.red}" #{object.content_length} bytes, modified #{object.last_modified}"
            # Thread.exclusive { log.info msg }
            rest_of_line = ""
            log_entries = object.read do |chunk|
                chunk = rest_of_line + chunk
                rest_of_line = ""
                chunk.each_line do |line|
                    if line[-1,1] == "\n" # full line
                        line.strip!
                        #log.debug "Full line   : #{line.green}"
                        s3ls.record line, myconn
                    else
                        #log.debug "Partial line: #{line.blue}"
                        rest_of_line = line
                    end
                end     
            end
        end
    end
    s3ObjectRunners.push th 
end

status_thread = Thread.new do 
    $stderr.print msg="Examining queue.".bold.blue
    last_msg_length = msg.length
    while filling || s3ObjectQueue.length > 0 

        msg = "Queue length: #{s3ObjectQueue.length.to_s.bold.blue}"
        msg += " and counting" if filling
        $stderr.print "%#{last_msg_length}s\r%s" % [ "", msg ]
        last_msg_length = msg.length
        sleep 1
    end
    $stderr.puts "%#{last_msg_length}s\r%s" % [ "", "Queue empty." ]
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
        # Thread.exclusive { log.debug object.key.yellow }
    end
end

filling = false

s3ObjectRunners.each do |thread|
    thread.join if thread.alive? 
end

status_thread.join if status_thread.alive?

puts JSON.pretty_generate( s3ls.to_hash )
