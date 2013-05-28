#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'mechanize'

# Temporary Config
STARTURL = "http://www.boston.com/bigpicture/"
BASEDIR = File.expand_path("~/tmp/bbp")
GETIMG = true

class BBPViewer
  def initialize()
    @agent = Mechanize.new
    @agent.user_agent_alias = 'Linux Firefox'
    @agent.cookie_jar.clear!
    @agent.follow_meta_refresh = true
    @agent.redirect_ok = true
  end

  def run()
    page = @agent.get(STARTURL)

    # stories hash containing all retrieved data
    # {name => [url,title,description,photocount,[[imgurl,caption],...]],...}
    stories = getrecentstories

    # Iterate over the stories
    stories.each do |name, data|
      data = parsestory(name, data)
    end
  end

  def getrecentstories()
    stories = {}
    # Search for available stories
    puts "Available stories:"
    @agent.page.search('.headDiv2/h2/a').each do |entry|
      url = entry['href']
      name = url.split('/').last.split('.').first
      title = entry.children.to_s
      stories[name] = [url,title]
      puts "#{title}: #{url}"
    end
    puts
    stories
  end

  def parsestory(name, data)
    # Get all available information and data of a story
    puts "Retrieving #{name}"
    url, title = data
    page = @agent.get(url)

    # Save the story description
    data.push(@agent.page.search('.bpBody').children.to_s)

    # Save the image count
    count = -1
    @agent.page.search('.bpBody').children.each do |element|
      if element.class == Nokogiri::XML::Element
        txt = element.children.to_s 
        if txt =~ /(\d+) photos total/
          count = txt.split(' ').first
        end
      end
    end
    data.push(count)

    # Save image captions
    captions = []
    @agent.page.search('.bpCaption').each do |caption|
      caption.children.each do |element|
        if element.class == Nokogiri::XML::Text
          captions.push(element.to_s)
        end
      end
    end

    # Save image URLs
    imgurls = []
    @agent.page.search('.bpImage').each do |img|
      url = img['src']
      imgurls.push(url)
    end

    # Merge image URLs and captions
    pictures = []
    imgurls.each_index do |i|
      pictures.push([imgurls[i],captions[i]])
    end
    data.push(pictures)
    data
  end


  def saveimg(stories)
    # Download images
    # Iterate over the stories
    stories.each do |name, value|
      puts "Downloading #{name}"
      url, title, description, photocount, pictures = value

      dir = "#{BASEDIR}/images/#{name}/full"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        pictures.each do |entry|
          @agent.get(entry.first).save
        end
      end
    end
  end

  def createhtml(stories)
    stories.each do |name, value|
      url, title, description, photocount, pictures = value

      unless File.exists?("#{BASEDIR}/lib")
        # Get the directory of the programm where a copy of the lib folder is located
        dir = File.expand_path $0
        dir = File.readlink(dir) if File.symlink?(dir)
        dir = File.dirname(dir)
        fail "No lib directory found" unless File.exists?("#{dir}/lib")
        FileUtils.mkdir_p BASEDIR
        FileUtils.cp_r "#{dir}/lib", BASEDIR
      end

      html = File.open("#{BASEDIR}/#{name}.html", 'w+')
      File.open("#{BASEDIR}/lib/gen_top.html", 'r') { |top| html.write(top.read) }
      pictures.each do |entry|
        url, alt = entry
        alt.gsub!(/'/,"&#39;")
        if(GETIMG)
          # Use local images
          imgdir = "images/#{name}"
          imgname = url.split('/').last
          tag = "        <li><a href='#{imgdir}/full/#{imgname}'><img src='#{imgdir}/full/#{imgname}' alt='#{alt}' /></a></li>"
        else
          # Use remote images
          tag = "        <li><a href='#{url}'><img src='#{url}' alt='#{alt}' /></a></li>"
        end
        html.puts(tag)
      end
      File.open("#{BASEDIR}/lib/gen_bottom.html", 'r') { |bot| html.write(bot.read) }
      html.close
    end
  end
end

bbpviewer = BBPViewer.new
stories = bbpviewer.run
bbpviewer.saveimg(stories) if GETIMG
bbpviewer.createhtml(stories)
