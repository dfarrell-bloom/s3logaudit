
require 'json'

class S3BucketLog

    def initialize bucket
        @bucket = bucket
        @accessors = []
        @actions = {}
        @first_access = nil
        @last_access = nil
        @requests = {}
    end

    def record parsed_entry
        @requests[ parsed_entry['request_id'] ] = parsed_entry
        if !@first_access || parsed_entry['time'] < @first_access
            @first_access = parsed_entry['time']
        end
        if !@last_access || parsed_entry['time'] > @last_access
            @last_access = parsed_entry['time']
        end
        unless @accessors.include? parsed_entry['requester'] 
            @accessors << parsed_entry['requester'] 
        end
        unless @actions[parsed_entry['requester']].kind_of? Array
            @actions[parsed_entry['requester']] = []
        end
        unless @actions[parsed_entry['requester']].include? parsed_entry['operation']
            @actions[parsed_entry['requester']] << parsed_entry['operation']
        end
    end

    def to_hash
        {   :bucket => @bucket,
            :accessors => @accessors,
            :actions => @actions,
            :first_access => @first_access,
            :last_access => @last_access,
            :requests => @requests
        }
    end

end

class S3LogSet

    attr_reader :bucket_logs

    def initialize
        @bucket_logs = {}
    end

    def record log_entry
        parsed_entry = self.class.parseLogEntry log_entry
        Thread.exclusive {
            unless @bucket_logs.has_key? parsed_entry['bucket']
                @bucket_logs[ parsed_entry['bucket'] ] = 
                    S3BucketLog.new parsed_entry['bucket']
            end
            @bucket_logs[ parsed_entry['bucket'] ].record parsed_entry
        }
    end
    
    def self.parseLogEntry entry
        # http://docs.aws.amazon.com/AmazonS3/latest/dev/LogFormat.html
        match = /^
            (?<owner>[^\s]+)\s
            (?<bucket>[^\s]+)\s
            \[(?<time>[^\]]+)\]\s
            (?<ip>[^\s]+)\s
            (?<requester>[^\s]+)\s
            (?<request_id>[^\s]+)\s
            (?<operation>[^\s]+)\s
            (?<key>[^\s]+)\s
            "(?<uri>[^"]+)"\s
            (?<status>[\d]+)\s
            (?<error>[^\s]+)\s
            (?<bytes_sent>[-\d]+)\s
            (?<object_size>[-\d]+)\s
            (?<total_ms>[\d]+)\s
            (?<turnaround_ms>[-\d]+)\s
            "(?<referrer>[^"]+)"\s
            "(?<user_agent>[^"]+)"\s
            (?<version_id>.*)
        $/x.match entry
        if match
            h = Hash.new
            %w{ 
            owner bucket time ip requester request_id operation 
            key uri status error bytes_sent object_size total_ms 
            turnaround_ms referrer user_agent version_id 
            }.each do |k|
                h[k] = match[k]
            end
            h['time'] = DateTime.strptime h['time'], "%d/%b/%Y:%H:%M:%S %z"
            return h
        else 
            raise LogParseError.new "Couldn't parse log entry: #{entry}"
        end
    end

    class LogParseError < Exception
    end

    def to_hash 
        h = Hash.new
        @bucket_logs.each do |bucket,bucketlog|
            h[bucket] = bucketlog.to_hash
        end
        h
    end

end
