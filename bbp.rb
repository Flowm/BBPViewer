#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'optparse'
require 'yaml'
require 'highline/import'
require 'mechanize'

class BostonBigPicture
  def self.run()
    agent = Mechanize.new
    agent.user_agent_alias = 'Linux Firefox'
    agent.cookie_jar.clear!
    agent.follow_meta_refresh = true
    agent.redirect_ok = true

    starturl = "http://www.boston.com/bigpicture/"
    basedir = "/tmp/site/"

    page = agent.get(starturl)

    stories = []
    puts "Available stories:"
    agent.page.search('.headDiv2/h2/a').each do |entry|
      title = entry.children.to_s
      link = entry['href']
      stories.push(link)
      puts "#{title}: #{link}"
    end
    puts

    stories.each do |url|
      page = agent.get(url)
      series_name = url.split('/').last.split('.').first
      dir = "#{basedir}/#{series_name}"
      puts "Downloading #{series_name}"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        agent.page.search('.bpImage').each do |img|
          path = img['src']
          #name = path.split('/').last
          agent.get(path).save
        end
      end
    end
  end
end

BostonBigPicture.run
