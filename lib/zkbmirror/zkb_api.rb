#!/usr/bin/env ruby

require 'rubygems'
require 'excon'

module ZkbMirror
  class ZkbApi
    def initialize(logger, debug, headers)
      @logger = logger
      @debug = debug
      @headers = headers.merge(default_headers)
      @base_url = 'https://zkillboard.com/api/'
    end

    def request(params)
      log "ZkbApi request start; params = #{params.inspect}"
      url = "#{@base_url}#{params.to_a.join('/')}/"
      response = Excon.get(url,
        :debug   => @debug,
        :headers => @headers)
      result = {:status => response.status, :headers => response.headers, :body => inflate(response.body)}
      log "ZkbApi request finish; status = #{result[:status]}, params = #{params.inspect}"
      result
    end

    private

    def log(msg)
      return if @logger.nil?
      @logger.info(msg)
    end

    def default_headers
      {
        'User-Agent'        => 'Maintainer: subfrowns <subfrowns@gmail.com>',
        'Accept-Encoding'   => 'gzip',
      }
    end

    def inflate(string)
      Zlib::GzipReader.new(StringIO.new(string)).read
      rescue Zlib::GzipFile::Error
        string
    end
  end
end
