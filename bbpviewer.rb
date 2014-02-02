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
THREADEDDL = false
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
    # {name => [url,title,description,date,photocount,[[imgurl,caption],...]],...}
    if ONLYRECENT
      stories = getrecentstories
    else
      stories = getallstories
    end

    # Iterate over the stories and get all data
    stories.each do |name, data|
      begin
        data = parsestory(name, data)
      rescue
        puts "Error retrieving story #{name}. Skipping."
        stories.delete(name)
      end
      if data[4].to_i < 1
        puts "Removing story #{name} as it contains no photos"
        stories.delete(name)
      end
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
      createindex(stories)
    end
  end

  def getrecentstories()
    @agent.get(BASEURL)

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
    (2014..2014).each do |year|
      (1..2).each do |month|
        begin
          @agent.get("#{BASEURL}/#{year}/#{sprintf("%2.2d", month)}/")
        rescue Mechanize::ResponseCodeError
          # No stories available for this month
          next
        end

        # Search for available stories
        puts "#{year}-#{sprintf("%2.2d", month)}:"
        @agent.page.search(".headDiv2/h2/a").each do |entry|
          url = entry['href']
          name = url.split('/').last.split('.').first
          title = entry.children.to_s
          stories[name] = [url,title]
          puts "#{title}: #{url}"
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
    @agent.get(url)

    # Save the story description
    data.push(@agent.page.search('.bpBody').children.to_s)

    # Save the story date
    data.push(Date.parse(@agent.page.search('.beLeftCol').children.children.to_s))

    # Save the image count
    count = -1
    @agent.page.search('.bpBody').children.each do |element|
      if element.class == Nokogiri::XML::Element
        txt = element.children.to_s
        if txt =~ /(\d+) photos total/
          count = txt.split(' ').first.to_i
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
      url, title, description, date, photocount, pictures = value

      dir = "#{BASEDIR}/images/#{name}"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        pictures.each do |picurl,desc|
          unless File.exists?("#{dir}/#{picurl.split('/').last}")
            @agent.get(picurl).save
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
      url, title, description, date, photocount, pictures = value

      dir = "#{BASEDIR}/images/#{name}"
      FileUtils.mkdir_p dir
      Dir.chdir(dir) do
        $threads = 0
        max_threads = 6
        pictures.each do |picurl,desc|
          Thread.new {
            $threads += 1
            #p "Create new Thread for img #{picurl}"
            unless File.exists?("#{dir}/#{picurl.split('/').last}")
              @agent.get(picurl).save
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
      url, title, description, date, photocount, pictures = value
      dir = "#{BASEDIR}/images/#{name}"

      unless File.directory?("#{dir}/thumbs")
        puts "Creating thumbnails for #{name}"
        FileUtils.mkdir_p "#{dir}/thumbs"
        Dir.chdir(dir) do
          system("mogrify -resize 450x300 -background black -gravity center -extent 450X300 -format jpg -quality 75 -path thumbs *.[jJ][pP][gG]")
        end
      end
    end
  end

  def createhtml(stories)
    stories.each do |name, value|
      url, title, description, date, photocount, pictures = value

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
      html.puts("\t\t<h1>#{title}</h1>\n\t</div>\n\n\t<ul id='Gallery' class='gallery'>")

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
      File.open("#{BASEDIR}/lib/gen_bot.html", 'r') { |bot| html.write(bot.read) }
      html.close
    end
  end

  def createindex(stories)
    html = File.open("#{BASEDIR}/index.html", 'w+')
    File.open("#{BASEDIR}/lib/index_top.html", 'r') { |top| html.write(top.read) }
    stories.sort_by{ |url, title, description, date, photocount, pictures| date }.each do |name, value|
      url, title, description, date, photocount, pictures = value
      p "#{name} #{date}"

      imgdir = "images/#{name}"
      imgname = pictures.first.first.split('/').last
      tag = "        <li><a href='#{name}.html'><h2>#{title}</h2><img src='#{imgdir}/thumbs/#{imgname}' alt='#{title}' /></a></li>"
      html.puts(tag)
    end
    File.open("#{BASEDIR}/lib/gen_bot.html", 'r') { |bot| html.write(bot.read) }
    html.close
  end
end

bbpviewer = BBPViewer.new
bbpviewer.run
