#!/usr/bin/env ruby

require 'rubygems'
require 'logger'
require 'json'
require 'excon'
require 'sequel'
require_relative 'zkbmirror/zkb_api.rb'

module ZkbMirror
  def self.init
    init_env
    init_database
  end

  def self.init_env
    @@debug = ENV['DEBUG'] == '1'
    @@logger = Logger.new(STDOUT)
    @@logger.level = @@debug ? Logger::DEBUG : Logger::INFO
    @@past_seconds = ENV['ZKB_PAST_SECONDS'] || '86400'
    @@database_url = ENV['DATABASE_URL'] || 'sqlite://kills.db'
    @@database = Sequel.connect(@@database_url, :logger => @@logger)
    @@dump_url = ENV['EVE_DUMP_URL'] || ENV['DATABASE_URL'] || 'sqlite://universeDataDx.db'
    @@dump = Sequel.connect(@@dump_url, :logger => @@logger)
  end

  def self.init_database
    @@database.create_table :kills do
      column :kill_id,            Integer,   primary_key: true
      column :kill_time,          Time
      column :solar_system_id,    Integer
      column :solar_system_name,  String
      column :region_id,          Integer
      column :region_name,        String
      column :ship_type_id,       Integer
      column :victim,             String
      column :character_id,       Integer
      column :character_name,     String
      column :corporation_id,     Integer
      column :corporation_name,   String
      column :alliance_id,        Integer
      column :alliance_name,      String
    end

    @@database.create_table :kill_attackers do
      foreign_key :kill_id, :kills
      column :character_id,       Integer
      column :character_name,     String
      column :corporation_id,     Integer
      column :corporation_name,   String
      column :alliance_id,        Integer
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
    @@dump[:mapRegions].select(:regionID).all.collect { |x| x.values }
  end

  def self.decode(string)
    JSON.parse(string)
  end

  def self.save_kill(kill)
    return if kill.nil?

    solar_system = @@dump[:mapSolarSystems][:solarSystemID => kill['solarSystemID']]
    region = @@dump[:mapRegions][:regionID => solar_system[:regionID]]

    @@database.transaction do

      exists = @@database[:kills][:kill_id => kill['killID']]
      raise Sequel::Rollback if exists

      @@database[:kills].insert(
        :kill_id            => kill['killID'],
        :kill_time          => kill['killTime'],
        :solar_system_id    => kill['solarSystemID'],
        :solar_system_name  => solar_system[:solarSystemName],
        :region_id          => region[:regionID],
        :region_name        => region[:regionName],
        :ship_type_id       => kill['shipTypeID'],
        :victim             => kill['victim']['victim'],
        :character_id       => kill['victim']['characterID'],
        :character_name     => kill['victim']['characterName'],
        :corporation_id     => kill['victim']['corporationID'],
        :corporation_name   => kill['victim']['corporationName'],
        :alliance_id        => kill['victim']['allianceID'],
        :alliance_name      => kill['victim']['allianceName'])
      
      kill['attackers'].each do |attacker|
        @@database[:kill_attackers].insert(
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

  def self.sync
    @@logger.info("Sync started; debug = #{@@debug}")
    start_time = Time.new
    zkb = ZkbApi.new(@@logger, @@debug, {})
    num_kills = 0

    regions.each do |regionID|
      page = 1

      while true do
        response = zkb.request(pastSeconds: @@past_seconds, regionID: regionID, shipTypeID: interesting_ships.join(','), page: page)

        break unless response[:status] == 200
        break if response[:body].nil? or response[:body].empty?

        body = decode(response[:body])
        break if body.nil? or body.empty?

        body.each do |k|
          next if k.nil?
          save_kill(k)
          num_kills += 1
        end

        break unless body.length == 200
        page += 1
      end
    end

    duration = Time.new - start_time
    @@logger.info("Sync complete; kill saved = #{num_kills}, took #{duration}s")
  end
end
