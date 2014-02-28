
# s3LogAudit

a tool to audit s3 bucket logs for accessors and thier actions

## Motivation 

I have a bunch of buckets to manage, and I want to know which ones aren't being used.


## Tests

<pre>
bundle install;
cd ./tests; 
rspect 
</pre>

## Usage 

All that is required is to `bundle install`, configure `keys.env` and then execute:

<pre>
bundle install
# edit s3keys.env from template, adding your AWS creds
cp s3keys.env.tpl s3keys.env
vim s3keys.env
# source it to load into your environment
. s3keys.env
# execute the audit program
./s3LogAudit.rb
vim
</pre>

