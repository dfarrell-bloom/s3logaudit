
export AWS_ACCESS_KEY_ID="your s3 key id" 
export AWS_SECRET_ACCESS_KEY="your s3 key secret"
export AWS_LOG_BUCKETS="your s3 log bucket name(s), space separated"

export MYSQL_HOST="your mysql host here"
export MYSQL_SOURCE_HOST="your ruby-side host here ( % would match any host)"
export MYSQL_USER="s3logaudit"
export MYSQL_PASSWORD="your password here"
export MYSQL_DATABASE="s3logaudit"

# a db create and grant command for you:
echo "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
GRANT ALL ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'${MYSQL_SOURCE_HOST}' IDENTIFIED by '${MYSQL_PASSWORD}';"
