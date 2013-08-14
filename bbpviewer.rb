#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'mechanize'

# Configuration
BASEURL = "http://www.boston.com/bigpicture"
# Temporary Settings
BASEDIR = File.expand_path("~/tmp/bbp")
ONLYRECENT = false
LOCALIMG = true
THREADEDDL = true
CREATEHTML = true


class BBPViewer
  def initialize()
    @agent = Mechanize.new
    @agent.user_agent_alias = 'Linux Firefox'
    @agent.cookie_jar.clear!
    @agent.follow_meta_refresh = true
    @agent.redirect_ok = true
  end

  def run()
    # stories hash containing all retrieved data
    # {name => [url,title,description,photocount,[[imgurl,caption],...]],...}
    if ONLYRECENT
      stories = getrecentstories
    else
      stories = getallstories
    end

    # Iterate over the stories and get all data
    stories.each do |name, data|
      data = parsestory(name, data)
    end
    puts

    # Optionally download the images
    if LOCALIMG
      if THREADEDDL
        saveimgthreaded(stories)
      else
        saveimg(stories)
      end
      # Create thumbnails
      createthumbs(stories)
    end

    # Finally create the html gallery
    if CREATEHTML
      createhtml(stories)
    end
  end

  def getrecentstories()
    page = @agent.get(BASEURL)

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

  def getallstories()
    stories = {}
    puts "Available stories:"
    (2013..2013).each do |year|
      (1..5).each do |month|
        begin
          page = @agent.get("#{BASEURL}/#{year}/#{sprintf("%2.2d", month)}/")
        rescue Mechanize::ResponseCodeError => msg  
          # No stories available for this month
          next
        end

        # Search for available stories
        puts "#{year}-#{sprintf("%2.2d", month)}:"
        @agent.page.search("/html/body/div/div/div/div[3]/div/table//tr").children.each do |tr|
          if tr.class == Nokogiri::XML::Element
            tr.children.each do |entry|
              if entry.class == Nokogiri::XML::Element && entry.name == "a"
                url = entry['href']
                name = url.split('/').last.split('.').first
                if entry.children.first.class == Nokogiri::XML::Text
                  title = entry.children.to_s
                  stories[name] = [url,title]
                  puts "#{title}: #{url}"
                end
              end
            end
          end
        end
        puts
      end
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
    # Downloads the images of the stories
    # Iterate over the stories
    stories.each do |name, value|
      puts "Downloading #{name}"
      url, title, description, photocount, pictures = value

      dir = "#{BASEDIR}/images/#{name}"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        pictures.each do |url,desc|
          unless File.exists?("#{dir}/#{url.split('/').last}")
            @agent.get(entry.first).save
          end
        end
      end
    end
  end

  def saveimgthreaded(stories)
    # Threaded version of saveimg
    # Iterate over the stories
    stories.each do |name, value|
      puts "Downloading #{name}"
      url, title, description, photocount, pictures = value

      dir = "#{BASEDIR}/images/#{name}"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        $threads = 0
        max_threads = 6
        pictures.each do |url,desc|
          Thread.new {
            $threads += 1
            #p Create new Thread for img #{url}
            unless File.exists?("#{dir}/#{url.split('/').last}")
              @agent.get(url).save
            end
            $threads -= 1
          }
          sleep 0.1
          #p Currently #{$threads} Threads running"
          while $threads >= max_threads
            # Don't start more then 10 concurrent threads
            sleep 0.1
          end
        end
        while $threads > 0
          # Wait for all image downloads of the current story to finish"
          sleep 1
        end
      end
    end
  end

  def createthumbs(stories)
    # Create thumbnails of the images
    stories.each do |name, value|
      url, title, description, photocount, pictures = value
      dir = "#{BASEDIR}/images/#{name}"

      unless File.directory?("#{dir}/thumbs")
        puts "Creating thumbnails for #{name}"
        FileUtils.mkdir_p "#{dir}/thumbs"
        Dir.chdir(dir) do
          system("mogrify -resize 450x300 -background black -gravity center -extent 450X300 -format jpg -quality 75 -path thumbs *.jpg")
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
        if LOCALIMG
          # Use local images
          imgdir = "images/#{name}"
          imgname = url.split('/').last
          tag = "        <li><a href='#{imgdir}/#{imgname}'><img src='#{imgdir}/thumbs/#{imgname}' alt='#{alt}' /></a></li>"
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
bbpviewer.run
