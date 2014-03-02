require_relative "../lib/S3BucketLog.rb"

bucket = "20120107-a"
example_log_entry = <<-eof
fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331 20120107-a [18/Feb/2014:01:05:48 +0000] 10.87.193.123 arn:aws:iam::269892434371:user/dfarrell 4252A222765A6A9D REST.GET.TAGGING - "GET /20120107-a?tagging HTTP/1.1" 404 NoSuchTagSet 278 - 85 - "-" "S3Console/0.4" -
eof
additional_log_entries = []
additional_log_entries.push <<-eof
fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331 bloom-prod-west1-backup [18/Feb/2014:07:40:51 +0000] - AmazonS3 16C0A391707CEAEE S3.TRANSITION.OBJECT sql/2013/11/prodwest-dbmaster/bloomhealth/mysqldump-15m-bloomhealth-D9440DF6-20131119-1300.sql.gz.gpg "-" - - - 737028378 - - "-" "-" -
eof
additional_log_entries.push <<-eof
fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331 bloom-production02-backup [27/Feb/2014:05:30:55 +0000] 66.41.101.112 fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331 6DC992B9A6790F79 REST.COPY.OBJECT_GET sql/2014/02/production02-mysql-01a/etl_enrollment/mysqldump-15m-etl_enrollment-D9440DF6-20140223-2351.sql.gpg - 200 - - 150260968 - - - - -
eof

parsed_entry=nil
expected_hash = nil 

describe S3LogSet do
    
    it "should raise S3LogSet::LogParseError on bad log entry" do 
        expect {
            S3LogSet.parseLogEntry "this is not a valid log entry"
        }.to raise_error S3LogSet::LogParseError
    end

    it "Should parse example log entry" do 
        match = S3LogSet.parseLogEntry example_log_entry
        match.should be_kind_of (Hash)
        match['owner'].should == "fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331"
        match['bucket'].should == "20120107-a"
        match['time'].should == DateTime.parse("2014-02-18T01:05:48+00:00")
        match['ip'].should == "10.87.193.123"
        match['requester'].should == "arn:aws:iam::269892434371:user/dfarrell"
        match['request_id'].should == "4252A222765A6A9D"
        match['operation'].should == "REST.GET.TAGGING"
        match['key'].should == "-"
        match['uri'].should == "GET /20120107-a?tagging HTTP/1.1"
        match['status'].should == "404"
        match['error'].should == "NoSuchTagSet"
        match['bytes_sent'].should == "278"
        match['object_size'].should == "-"
        match['total_ms'].should == "85"
        match['turnaround_ms'].should == "-"
        match['referrer'].should == "-"
        match['user_agent'].should == "S3Console/0.4"
        match['version_id'].should == "-"
        parsed_entry = match
        expected_hash = { 
            :bucket => bucket, 
            :accessors => [ parsed_entry['requester'] ] ,
            :actions => { parsed_entry['requester'] => [ parsed_entry['operation'] ] },
            :first_access => parsed_entry['time'],
            :last_access => parsed_entry['time'],
            # :requests => { parsed_entry['request_id'] => parsed_entry },
            :request_count => 1
        }
    end


end

describe S3BucketLog do
    s3bl = nil
    it "Should initialize with bucket name" do
        s3bl = S3BucketLog.new bucket
    end

    it "Should provide hash initized to bucket name and nils" do
        h = s3bl.to_hash
        h.should be_kind_of Hash
        h.should == {
            :bucket => bucket, 
            :accessors => [],
            :actions => {},
            :first_access => nil, 
            :last_access => nil, 
            # :requests => {},
            :request_count => 0
        }
    end

    it "Should record a parsed log entry" do
        s3bl.record parsed_entry
    end
    
    it "Should provide a hash with data from parsed log entry" do
        h = s3bl.to_hash
        h.should be_kind_of Hash
        h.should == expected_hash
    end



end

describe S3LogSet do
    s3ls = nil
    conn = nil
    it "Should initiaize cleanly" do
        s3ls = S3LogSet.new 
    end

    it "should output valid MySQL REPLACE query" do
         conn = Mysql2::Client.new(
            :host => ENV['MYSQL_HOST'],
            :username => ENV['MYSQL_USER'],
            :password => ENV['MYSQL_PASSWORD'],
            :database => ENV['MYSQL_DATABASE']
        )
        q = s3ls.class.insertQuery parsed_entry, conn
    end

    it "should record log entry without database connection" do
        s3ls.record example_log_entry
    end

    it "should supply hash of each log entry" do
        s3ls.to_hash.should == { bucket => expected_hash }
    end

    it "Should parse other log entries (which has failed in the past) with database connection" do
        additional_log_entries.each do |entry|
            s3ls.record entry, conn
        end
    end
    
    it "should supply hash of each log entry" do
        s3ls.to_hash.should == { bucket => expected_hash,
            "bloom-prod-west1-backup" => {
                :bucket=>"bloom-prod-west1-backup",
				:accessors=>["AmazonS3"],
				:actions=>{"AmazonS3"=>["S3.TRANSITION.OBJECT"]},
				:first_access=> DateTime.parse("2014-02-18T07:40:51+00:00"),
				:last_access=> DateTime.parse("2014-02-18T07:40:51+00:00"),
                :request_count => 1,
=begin
				:requests=>{   "16C0A391707CEAEE"=>{
	                "owner"=>"fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331",
				    "bucket"=>"bloom-prod-west1-backup",
				    "time"=> DateTime.parse("2014-02-18T07:40:51+00:00"),
					"ip"=>"-",
					"requester"=>"AmazonS3",
					"request_id"=>"16C0A391707CEAEE",
					"operation"=>"S3.TRANSITION.OBJECT",
					"key"=>"sql/2013/11/prodwest-dbmaster/bloomhealth/mysqldump-15m-bloomhealth-D9440DF6-20131119-1300.sql.gz.gpg",
					"uri"=>"-",
					"status"=>"-",
					"error"=>"-",
					"bytes_sent"=>"-",
					"object_size"=>"737028378",
					"total_ms"=>"-",
					"turnaround_ms"=>"-",
					"referrer"=>"-",
					"user_agent"=>"-",
					"version_id"=>"-"
                    }
	             }
=end
	        },
            "bloom-production02-backup" => {
                :bucket=>"bloom-production02-backup", 
                :accessors=>["fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331"], 
                :actions=>{"fa0120f03b0f093488ef26e8299feb9fc737d7d2929b9094be71b99fed14e331"=>["REST.COPY.OBJECT_GET"]}, 
                :first_access=> DateTime.parse("2014-02-27T05:30:55+00:00"), 
                :last_access => DateTime.parse("2014-02-27T05:30:55+00:00"), 
                :request_count=>1
            }
        }
    end

    
end
