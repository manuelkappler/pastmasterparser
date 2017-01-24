#!/usr/bin/ruby

require 'nokogiri'
require 'open-uri'

BASE_URI = "http://library.nlx.com/xtf/"
VOLUME_ADDERS = {'ew'=> 0, 'mw'=> 5, 'lw'=> 20}

class Book

  # Creates a Book object given a period and volume. 
  # This is still Dewey-specific. 
  # (Evenutally, we would want a menu that lets you select from all the possible options and which passes the URL to the book parser)
  # TODO: Make this non-Dewey specific
   
  def initialize(period, volume)

    # puts "Trying to generate a PDF for Dewey's volume #{volume} of #{period}"
    if not ['ew', 'mw', 'lw'].include? period
      puts "Choose ew, mw, or lw for the period"
    end
    running_volume_number = volume.to_i + VOLUME_ADDERS[period]
    url = "#{BASE_URI}view?docId=dewey_ii/dewey_ii.#{(running_volume_number).to_s.rjust(2, '0')}.xml;chunk_id=div.mw.100.1;toc.depth=1"
    puts url
     
    Dir.mkdir("#{period}#{volume}") unless Dir.exists? "#{period}#{volume}"
    
    Dir.chdir("#{period}#{volume}") do
    # Download the HTML file only if it doesn't exist yet 
    
      begin
        file = open("#{period}.#{volume}.html", 'r')
      rescue
        begin
          puts "File not yet downloaded. Starting download"
          file = open("#{period}.#{volume}.html", 'w')
          download = open(url)
          file.write(download.read)
          file = open("#{period}.#{volume}.html", 'r')
        rescue
          # TODO: Better error handling
          puts "something went wrong downloading the file"
        end
      end
      # Now that we have the HTML file, create the Nokogiri tree
      @html = file.read
    end
    @noko = Nokogiri::HTML(@html)
    # This selects the Volume in the TOC tree (on the left) from which we get the individual pages
    @volume = @noko.css(".selectedVolume")[0]

    # This is the only thing we get from the initial page, all other data is in the individual chapters 
    
    @collection_title = @noko.xpath("//div[contains(@class, 'collection_title')]").text.strip
    @volume_title = @noko.xpath("//div[contains(@class, 'volume_title')]").text.strip

    # TODO: This shouldn't be hardcoded
    @author = {:first=>'John', :last=>'Dewey'}

    puts "Found #{@collection_title}, #{@volume_title}"

    # Note that the entire magic happens when calling this command. It'll download the section files and parse them
    
    normal_links = "//div[contains(@class, 'l1')]/a"
    active_link = "//a[../following-sibling::td/div/span[@class='toc-hi']]"

    link_nodes = @volume.xpath("#{normal_links} | #{active_link}")

    sections = {}

    link_nodes.each do |ln|

      unless ln.text == ""
        sections[ln.text.strip.split.map(&:capitalize).join('')] = ln[:href]
      else
        sections[ln.xpath("../following-sibling::td/div/span[@class='toc-hi']").text.strip.split.map(&:capitalize).join('')] = ln[:href]
      end
    end
    #puts sections

    @structure = parse_toc_links(sections, period, volume)

    # This (over)-writes the parsed file
    
    mdname = "#{@author[:last]}__#{period}#{volume}.md"

    file = open(mdname, 'w')
    file.write(generate_preamble)

    @structure.each do |section|
      file.write(section.content)
    end

    puts "Running Pandoc now"
    vol_content = /Volume \d{1,2}: \d{4}(?:-\d{4})?, (?<content>.*)/.match(@volume_title)[:content].split(',').map(&:strip).map{|x| if /\Aand (?<t>.*)/.match(x); /\Aand (?<t>.*)/.match(x)[:t]; else x; end}.map{|x| x.gsub!(/[:]/, '_'); x.gsub(/-/, '')}. map(&:split).map{|x| x.map(&:capitalize)}.map(&:join).join('_')
    pdfname = "#{@author[:last]}__#{period.upcase}#{volume}__#{vol_content}.pdf"

    pandoc = system("pandoc --latex-engine=xelatex --template=book.latex --toc #{mdname} -o #{pdfname}")
    if pandoc
      puts "Created PDF file and saved as #{pdfname}"
    else
      puts "Error creating PDF file. Parsed Markdown file saved as #{mdname}"
    end
    
  end


  # Receives an array of links to the sections of the book. Downloads the html files if necessary and creates the section objects (note that this parses the sections at the moment)
  def parse_toc_links(chapters, period, volume)
    #puts "Parsing #{@volume_title}"
    structure = []
    chapters.each do |filename, url|
      puts "Downloading section #{filename} at #{url}"
      puts "#{BASE_URI}#{url}"
      file = nil
      Dir.chdir("#{period}#{volume}") do
        begin
          file = open("#{period}_#{volume}__#{filename}.html", 'r')
          puts "File already dowloaded. Skipping"
        rescue
          puts "File not downloaded yet. Downloading"
          file = open("#{period}_#{volume}__#{filename}.html", 'w')
          begin
            download = open("#{BASE_URI}#{url}")
          rescue
            puts "Fatal Error: could not download #{BASE_URI}#{url}"
            raise "Download Error"
          end
          file.write(download.read)
        end

      end
      puts "Parsing and appending new section for #{filename}"
      structure << Section.new(period, volume, filename, file)

    end

    return structure

  end

  def generate_preamble
    return """---
title: \"#{/Volume.*/.match(@volume_title)}\"
subtitle: \"#{/(?<series>.*)\. Volume/.match(@volume_title)[:series]} in #{@collection_title}\"
author: \"#{@author[:first]} #{@author[:last]}\"
date: 1996
publisher: Center for Dewey Studies
geometry: left=0.5in, right=0.5in, bottom=0.5in
classoption: book,twoside,12pt
documentclass: memoir
mainfont: Minion Pro
mainfontoptions: BoldFont=Myriad Pro Bold
sansfont: Myriad Pro
papersize: ebook
ismemoir: True
toc: True
..."""
  end

end

class Section

  attr_reader(:content)

  def initialize(period, volume, name, file)
    @period = period
    @volume = volume
    @section_name = name
    Dir.chdir("#{period}#{volume}") do
      @noko = Nokogiri::HTML(file)
      strip_content
      file = "#{@period}_#{@volume}_#{@section_name}_parsed.md"
      wfile = open(file, 'w')
      content = @noko.xpath("//div[contains(@id, 'article_content')]").to_html
  # Do some last-minute regex on the document
      # Merge footnotes that are immediately subsequent to each other
      @content = content.gsub(/\^\[(?<fn1>.*)\]\^\[(?<fn2>.*)\]/, '^[\k<fn1> **consecutive footnote merged**: \k<fn2>]')
      # Remove any leftover divs
      @content = @content.gsub(/(<div.*>|<\\div>)/, '')
      #puts @content.slice(0, 200)
      wfile.write(@content)
      wfile.close
    end
  end

  def strip_content

# Footnotes 
    # Turn spans preceded by endnote attribute into markdown footnotes
    spans = @noko.xpath("//span[preceding-sibling::a[1][contains(@endnote, '1')] and following-sibling::span[1][contains(@name, 'footnote')]]")
    spans.each{|span| 
      span.previous_element.remove; 
      span.next_element.remove; 
      text = span.text.strip.gsub(/\n/, ' ')
      t_array = text.split
      text = []
      t_array.each_with_index{|word, idx|
        unless idx == t_array.length - 2
          unless word.gsub(/-/, '') == t_array[idx + 1]
            text << word
          end
        end
      }
      if span.xpath("ancestor::h2|ancestor::h4").length > 0
        heading = span.xpath("ancestor::h2|ancestor::h4")
        # puts heading.text
        new_node = Nokogiri::XML::Node.new "text", @noko
        new_node.content = "^[#{text.join(" ").gsub(/\n/, ' ')}]"
        heading.children[-1].add_next_sibling new_node
        span.remove
        # puts heading.text
      else
        span.replace("^[#{text.join(" ").gsub(/\n/, ' ')}]")
      end
    }
    # remove sups and spans that only hyphenate words
    sups = @noko.xpath("//sup[following-sibling::span]")
    #puts sups.length
    spans = @noko.xpath("//span[preceding-sibling::sup/a[contains(@class, 'cluetip')]]")
    #puts spans.length
    sups.each{|sup| sup.traverse{|n| n.remove }}
    spans.each{|span| span.remove} 

## References are tricky. Make use of markdowns named reference system to resolve them when the document is put together.
    # The original html doesn't separate the location of the reference from their target well. However, (it seems that) in-text references are marked by a "a" at the end of their name, whereas the target has a "r"
     
    references = @noko.xpath("//a[@reference and preceding-sibling::a and following-sibling::a]")
    for ref in references
      ref.previous_element.remove
      ref.next_element.remove
      #puts ref.parent.name
      if ref[:name][-1] == 'r'
        # If refs are in Endmatter
        if ["hang pad", "hang"].include? ref.parent['class']
          ref.parent.replace("Endnote included in running text as footnote.\n\n")
        else
          endnote = "[^#{ref[:name].gsub(/\..{1,2}\z/, '')}]"
          ref.replace("#{endnote}: #{ref.parent.text}")
        end
        # If ref is in body
      elsif ref['name'][-1] == 'a'
        endnote = "[^#{ref[:name].gsub(/\..{1,2}/, '')}]"
        if ["h1", "h2", "h3", "h4"].include? ref.parent.name
          #puts ref.parent.inspect
          ref.parent.text.replace(ref.parent.text + endnote)
        else
          ref.replace(endnote)
        end
      else
        #puts "#### Problem with reference parsing, could not determine the status of this reference:"
        #puts ref.inspect
      end
    end

# Strip page numbers
    puts("Stripping page numbers")
    pagenumbers = @noko.xpath("//span[contains(@class, 'run-head')]")
    for pn in pagenumbers
      number = /((?:lw|ew|mw)\.)?(\d{1,2}\.)?(\d{1,4}|[ixv]{1,5})/.match(pn.text)
      #puts pn.parent
      pn.parent.replace(" **(#{number})** ")
    end

# Formatting
    # Italics
    puts("Parsing formatting")
    @noko.xpath("//i").each{|i| i.replace("*#{i.text}*")}
    @noko.xpath("//b").each{|b| b.replace("**#{b.text}**")}
    # Linebreaks
    puts("Stripping linebreaks")
    breaks = @noko.xpath("//br")
    for br in breaks
      br.remove
    end
## At the moment, parsing tables is too complicated and they are usually non-essential. 
# TODO: Implement table parsing
     
    # Tables
    
    tables = @noko.xpath("//div[contains(@id,'article_content')]//table")
    # puts tables
    tables.each do |table|
      table.replace("Table removed for now")
    end

    
# Headers
    puts("Parsing headers")
    titles = @noko.xpath("//h4[contains(@class, 'normal')]")
    titles.each_with_index do |h4, index|
      text = h4.text.strip.gsub("\n", '')
      if index == 0
        # Handle long chapter headings (for PDF Header)
        # If the heading without footnotes is longer than 40 characters
        if text.match(/(?<title>.*?)(?<fn>\^\[.*)?/)[:title].length > 40
          puts "Found a title longer than 40 characters: #{text}"
          # If the first sentence is less than 40 chars use it instead
          if text.split(".")[0].length < 40
            h4.replace("\n\n# #{text}\n\\chaptermark{#{text.split(".")[0]}}\n\n")
          # If not, abbreviate to a max length of 40
          else
            h4.replace("\n\n# #{text}\n\\chaptermark{#{text.slice(0, 37).rstrip + "..."}}\n\n")
          end
        else
          h4.replace("\n\n# #{text}\n\n")
        end
      else
        h4.replace("\n\n### #{text}\n\n")
      end
    end
    # Replace h2 headers with 2nd level headings
    @noko.xpath("//h2[contains(@class, 'normal')]").each{|h2| h2.replace("\n\n## #{h2.text.gsub(/\n/, '')}\n\n")}

#Strip paragraphs
    puts("Stripping paragraphs")
    content_paragraphs = @noko.xpath("//p[contains(@class, 'tbindent')]")
    for p in content_paragraphs
      p.replace("\n\n#{p.text.strip}")
    end
    block_paragraphs = @noko.xpath("//p[contains(@class, 'block')]")
    for p in block_paragraphs
      p.replace("\n\n#{p.text.split("\n").map{|x| "| " + advanced_strip(x) + "\n"}.join}\n")
    end
    center_paragraphs = @noko.xpath("//p[contains(@class, 'center')]")
    for p in center_paragraphs
      p.replace("\n\n#{p.text.strip}")
    end
    # normal paragraphs
    @noko.xpath("//p[contains(@class, 'normal')]").each{|n| n.replace("\n\n#{n.text.strip}")}
    # spacer paragraphs
    @noko.xpath("//p[contains(@class, 'spacer')]").each{|s| s.remove}
    # hang paragraphs
    @noko.xpath("//p[contains(@class, 'hang')]").each{|h| h.replace("\n\n#{h.text.strip}")}
    # indented paragraphs
    @noko.xpath("//p[contains(@class, 'indent_')]").each{|h| puts h.text; puts (/indent_(?<ind>\d{1,2})em/.match(h['class'])[:ind].to_i); text = "\n\n|    #{'  ' * (/indent_(?<ind>\d{1,2})em/.match(h['class'])[:ind].to_i / 2)} #{h.text}"; puts text; h.replace(text)}
    
    remaining_paragraphs = @noko.xpath("//p")
    for p in remaining_paragraphs
      puts p
    end
  end

  def advanced_strip x
    return x.gsub!(/\A[[:space:]]*/, '').gsub!(/[[:space:]]*\z/, '')
  end

end


Book.new(ARGV[0], ARGV[1])
