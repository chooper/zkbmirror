#!/usr/bin/env ruby

require 'rubygems'
require 'excon'

module ZkbMirror
  class ZkbApi
    def initialize(headers, cache, debug)
      @headers = headers.merge(default_headers)
      @cache = cache
      @debug = debug
      @base_url = 'https://zkillboard.com/api/'
    end

    def request(params)
      url = "#{@base_url}#{params.to_a.join('/')}/"

      @cache.cache(url) do
        response = Excon.get(url,
          :debug   => @debug,
          :headers => @headers)
        {:status => response.status, :headers => response.headers, :body => inflate(response.body)}
      end
    end

    private

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
