#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
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

    # stories hash containing all information
    # {name => [url,title,[[caption,imgurl],..]
    stories = {}

    # Search for available stories
    puts "Available stories:"
    agent.page.search('.headDiv2/h2/a').each do |entry|
      url = entry['href']
      name = url.split('/').last.split('.').first
      title = entry.children.to_s
      stories[name] = [url,title]
      puts "#{title}: #{url}"
    end
    puts

    # Iterate over the stories
    stories.each do |name, value|
      url, title = value
      page = agent.get(url)
      puts "Saving #{name}"

      # Save image captions
      captions = []
      agent.page.search('.bpCaption').each do |caption|
        caption.children.each do |element|
          if element.class == Nokogiri::XML::Text
            captions.push(element.to_s)
          end
        end
      end

      # Save image URLs (and download?)
      imgurls = []
      dir = "#{basedir}/#{name}"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        agent.page.search('.bpImage').each do |img|
          url = img['src']
          imgurls.push(url)
          #agent.get(url).save
        end
      end

      # Merge imgurls with captions
      pictures = []
      imgurls.each_index do |i|
        pictures.push([imgurls[i],captions[i]])
      end
      stories[name].push(pictures)
    end
    puts
    puts stories
  end
end

BostonBigPicture.run
