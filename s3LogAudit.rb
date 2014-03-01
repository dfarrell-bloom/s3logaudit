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

s3 = AWS::S3.new

def query_or_fail conn, q
    begin 
        conn.query q
    rescue Mysql2::Error => e 
        raise Exception.new "Error executing SQL Query: \033[33m#{q}\033[0m\n" +
            "MySQL Error #{e.errno} : #{e.message}"
        return false
    end
end

begin 
    masterconn = Mysql2::Client.new( 
        :host => ENV['MYSQL_HOST'], 
        :username=> ENV['MYSQL_USER'], 
        :password=> ENV['MYSQL_PASSWORD'],
        :database => ENV['MYSQL_DATABASE']
    )
    query_or_fail masterconn, "CREATE TABLE IF NOT EXISTS buckets ( 
        name VARCHAR(255) NOT NULL PRIMARY KEY, 
        logging_enabled BOOLEAN NOT NULL,
        log_destination VARCHAR(255) DEFAULT NULL,
        log_prefix VARCHAR(255) DEFAULT NULL,
        is_log_destination BOOLEAN DEFAULT FALSE,
        `empty` BOOLEAN NOT NULL
    ) ENGINE=InnoDB CHARACTER SET utf8"
    query_or_fail masterconn,  "CREATE TABLE IF NOT EXISTS log_entries ( 
        request_id CHAR(16) CHARACTER SET ascii NOT NULL,
        PRIMARY KEY(request_id),
        operation VARCHAR(255), 
        KEY( operation ), 
        owner VARCHAR(255) NOT NULL, 
        bucket VARCHAR(255) NOT NULL, 
        CONSTRAINT FOREIGN KEY( bucket ) REFERENCES buckets (name) 
            ON DELETE CASCADE ON UPDATE CASCADE,
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
    ) ENGINE=InnoDB CHARACTER SET utf8"
    s3.buckets.each do |bucket|
        log.debug "Examining logging on bucket #{bucket.name}"
        logging_data = s3.client.get_bucket_logging( :bucket_name => bucket.name )
        if logging_data.has_key? :logging_enabled
            logging_enabled =  'TRUE' 
            logging_data = logging_data[:logging_enabled]
            log_destination = "'#{masterconn.escape logging_data[:target_bucket]}'"
            log_prefix = "'#{masterconn.escape logging_data[:target_prefix]}'"
        else
            logging_enabled =  'FALSE' 
            log_destination = 'NULL'
            log_prefix = "NULL"
        end
        empty = ( bucket.empty? ? 'TRUE' : 'FALSE' )
        log.info "Recording bucket #{bucket.name} and logging properties"
        query_or_fail masterconn,  "REPLACE INTO buckets SET 
            name = '#{ masterconn.escape bucket.name }', 
            empty = #{ empty },
            logging_enabled = #{logging_enabled},
            log_destination = #{log_destination},
            log_prefix = #{log_prefix}
        "
    end
    query_or_fail masterconn,  "
        UPDATE buckets logb
        JOIN buckets b 
            ON b.log_destination = logb.name
        SET logb.is_log_destination = TRUE 
    "
    failed = false

rescue Exception => e 
    log.fatal "Error Creating bucket list: #{e.class.name}: #{e.message} \n  #{e.backtrace.join "\n\t"}"
    failed = true   
ensure
    masterconn.close if masterconn
    exit 125 if failed
end 


s3ObjectQueue = Queue.new
s3ObjectRunners = Array.new
filling = true

s3ls = S3LogSet.new

config[:object_threads].times do 
    th = Thread.new do 
       myconn = Mysql2::Client.new( 
            :host => ENV['MYSQL_HOST'], 
            :username=> ENV['MYSQL_USER'], 
            :password=> ENV['MYSQL_PASSWORD'],
            :database => ENV['MYSQL_DATABASE']
        )
        while filling || ( s3ObjectQueue.length > s3ObjectQueue.num_waiting  )
            begin 
                # timeout avoids race on filling set to false after thread begins waiting
                object = Timeout::timeout( config[:queue_timeout] ) { 
                    object = s3ObjectQueue.pop 
                }
            rescue Timeout::Error
                next # try again
            end
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
        myconn.close()
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
