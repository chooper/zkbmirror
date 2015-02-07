#!/usr/bin/env ruby

require 'rubygems'
require 'logger'
require 'json'
require 'excon'
require 'sequel'
require 'diskcached'

# check for debug mode
$debug = ENV['DEBUG'] == '1'

$logger = Logger.new(STDOUT)
$logger.level = $debug ? Logger::DEBUG : Logger::INFO

$cache = Diskcached.new

module ZkbMirror
  def self.database
    $conn ||= Sequel.connect("sqlite://kills.db", :logger => $logger)
  end

  def self.init_database
    database.create_table :kills do
      column :kill_id,            String,   primary_key: true
      column :kill_time,          Time
      column :solar_system_id,    String
      column :ship_type_id,       String
      column :victim,             String
      column :character_id,       String
      column :character_name,     String
      column :corporation_id,     String
      column :corporation_name,   String
      column :alliance_id,        String
      column :alliance_name,      String
    end

    database.create_table :kill_attackers do
      foreign_key :kill_id, :kills
      column :character_id,       String
      column :character_name,     String
      column :corporation_id,     String
      column :corporation_name,   String
      column :alliance_id,        String
      column :alliance_name,      String
    end
    rescue Sequel::DatabaseError
      nil
  end

  def self.interesting_ships
    [
      32250,  # sbu
      32226,  # tcu
      32458,  # ihub
    ]
  end

  def self.regions
    url = "http://www.evedata.org/JSON/marketRegionList.cgi"
    $cache.cache(url) do
      response = Excon.get(url)
      decode(response.body).collect { |o| o["regionID"] }
    end
  end

  def self.inflate(string)
    Zlib::GzipReader.new(StringIO.new(string)).read
    rescue Zlib::GzipFile::Error
      string
  end

  def self.decode(string)
    JSON.parse(string)
  end

  def self.save_kill(kill)
    database.transaction do

      exists = database[:kills][:kill_id => kill['killID']]
      raise Sequel::Rollback if exists

      database[:kills].insert(
        :kill_id            => kill['killID'],
        :kill_time          => kill['killTime'],
        :solar_system_id    => kill['solarSystemID'],
        :ship_type_id       => kill['shipTypeID'],
        :victim             => kill['victim']['victim'],
        :character_id       => kill['victim']['characterID'],
        :character_name     => kill['victim']['characterName'],
        :corporation_id     => kill['victim']['corporationID'],
        :corporation_name   => kill['victim']['corporationName'],
        :alliance_id        => kill['victim']['allianceID'],
        :alliance_name      => kill['victim']['allianceName'])
      
      kill['attackers'].each do |attacker|
        database[:kill_attackers].insert(
          :kill_id            => kill['killID'],
          :character_id       => attacker['characterID'],
          :character_name     => attacker['characterName'],
          :corporation_id     => attacker['corporationID'],
          :corporation_name   => attacker['corporationName'],
          :alliance_id        => attacker['allianceID'],
          :alliance_name      => attacker['allianceName'])
      end
    end
  end

  def self.zkb_request(params)
    url = "https://zkillboard.com/api/#{params.to_a.join('/')}/"
    # protip: you can bypass cache enforcement by joining/appending alliance IDs

    $cache.cache(url) do
      response = Excon.get(url,
        :debug   => $debug,
        :headers =>
          {
            'User-Agent'        => 'Maintainer: subfrowns <subfrowns@gmail.com>',
            'Accept-Encoding'   => 'gzip',
          }
      )
      {:status => response.status, :headers => response.headers, :body => inflate(response.body)}
    end
  end

  def self.sync
    regions.each do |regionID|
      response = zkb_request(pastSeconds: 86400, regionID: regionID, shipTypeID: interesting_ships.join(','))
      if response[:status] == 200
        body = decode(response[:body])
        next if body.nil? or body.empty?
        body.each { |kill| save_kill(kill) }
      end
    end
  end
end
