#!/usr/bin/env ruby

require 'sinatra'
require 'mysql2'
require 'erubis'
require 'json'

class QueryException < Exception
    attr_reader :query
    def initialize e, query
        @query = query
        super "Query failed to execute.  MySQL Errno #{e.errno}: #{e.message}"
    end
end

helpers do
    def sqlConnect 
        Mysql2::Client.new( 
            :host => ENV['MYSQL_HOST'],
            :username=> ENV['MYSQL_USER'],
            :password=> ENV['MYSQL_PASSWORD'],
            :database => ENV['MYSQL_DATABASE']  )   
    end
 
    def executeQuery conn, query, setup = nil, cleanup = nil
        err = nil
        $stderr.puts "Executing query: \033[33m#{query}\033[0m"
        begin
            result = conn.query query
        rescue Mysql2::Error => e
            err = QueryException.new e, query
            result = false
        ensure   
            raise err if err.kind_of? Exception
        end  
        result
    end

    def generateData  query, setup = ni, cleanup = nil
        myconn = sqlConnect
        begin
            if setup
                setup = [ setup ] unless setup.kind_of? Array
                setup.each { |q| executeQuery myconn, q }
            end
            result = executeQuery myconn, query      
            if cleanup
                cleanup = [ cleanup ] unless cleanup.kind_of? Array
                cleanup.each { |q| executeQuery myconn, q }
            end
        ensure
            myconn.close if myconn
        end
        return result
    end
end

def loadAudits auditsfile = "audits.json"
    JSON.parse( File.read  auditsfile )
end

def loadInfo infofile = "info.json"
    JSON.parse( File.read  infofile )
end

before %r{/(audits|info)} do 
    default_renderer = Proc.new { |value|
        value
    }
    @renderers = Hash.new( default_renderer )
    @renderers["bucket"] = Proc.new { |value|
        "<a href=\"/info/buckets/#{value}\">#{value}</a>"
    }
    @renderers["Requester Bucket Operations"] = Proc.new { |value|
        if value.kind_of? String
        result = "<ul>"
        value.split(' ').each do |word|
            result << "<li>#{word}</li>"
        end
        result << "</ul>"
        else
            value
        end
    }
    @renderers["Object Operations"] = @renderers["Requester Bucket Operations"]
    @renderers["log_destination"] = @renderers["bucket"] 
end

before %r{^/audits} do
    @audits = loadAudits()
    @auditRenderers = Hash.new( Proc.new { |audit| 
        Proc.new { 
            begin
                results = generateData audit['query'] , audit['setup'], audit['cleanup']
                erb :"#{audit['tpl']}", :locals => { :results => results, :renderers => @renderers }
            rescue QueryException => e 
                erb :queryError, :locals => { :e => e }
            end
        }
    })
end

before %r{^/info} do
    @info = loadInfo()
    @infoRenderers = Hash.new( Proc.new { |info| 
        Proc.new { 
            begin
                results = executeQuery info['query'] 
                erb :"#{info['tpl']}", :locals => { :results => results, :renderers => @renderers  }
            rescue QueryException => e 
                erb :queryError, :locals => { :e => e }
            end
        }
    })
    @infoRenderers['bucketlisting']  
end


get "/" do
    redirect "/index.html", 302
end

get "/index.html" do 
    erb :index
end

### Audits

get "/audits/*" do
    id = params[:splat][0]
    unless @audits.has_key? id
        halt 404
    end
    erb :audit, :locals =>  { :audit => @audits[ id ] } , &(@auditRenderers[ @audits[id]['renderer'] || id ].call( @audits[id ] ) )
end 

get "/audits/" do
    redirect "/audits", 302
end 

get "/audits" do
    erb :listing, :locals => { :title => "Audits", :subtitle => "Each audit check is shown below", :base_url => "/audits", :entries => @audits }
end


## Results Browser

get "/info/" do
    redirect "/info", 302
end

get "/info/buckets/:name" do 
    erb "<p>Placeholder: Bucket information for bucket <code>#{params[:name]}</code> should be shown</p>"
end

get "/info/*" do
    id = params[:splat][0]
    unless @info.has_key? id
        halt 404
    end
    erb :info, :locals =>  { :info => @info[ id ] } , &(@infoRenderers[ @info[id]['renderer'] || id  ].call( @info[id ] ) )
end

get "/info" do 
    erb :listing, :locals => { :title => "Information", :subtitle => "Available information is shown below", :base_url => "/info", :entries => @info }
end

