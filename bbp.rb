#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'optparse'
require 'yaml'
require 'highline/import'
require 'mechanize'

class BostonBigPicture
  def self.run()
    config

    agent = Mechanize.new
    agent.user_agent_alias = 'Linux Firefox'
    agent.cookie_jar.clear!
    agent.follow_meta_refresh = true
    agent.redirect_ok = true

    page = agent.get(@@cfg[:url])

    agent.page.search('.headDiv2/h2/a').each do |entry|
      title = entry.children.to_s
      link = entry['href']
    end
  end

  def self.config()
    @@cfg = {}
    @@cfg[:url] = "http://www.boston.com/bigpicture/"
  end
end

BostonBigPicture.run
