#!/usr/bin/env ruby

require 'scraperwiki'
require 'mechanize'
require 'uri'
require 'date'
require 'open-uri'
require 'rexml/document'
require 'fileutils'
require 'logger'

@logger = Logger.new(STDOUT)

def pdftoxml(data)
  src = Tempfile.new(['pdftohtml_src.', '.pdf'])
  src.write(data.read)
  src.close

  command = ['/usr/bin/pdftohtml', '-xml', '-f', '1', '-l', '1', '-nodrm', '-zoom', '1.5', '-enc', 'UTF-8', '-noframes', '-stdout', src.path]
 
  IO.popen(command, :err => [:child, :out]) do |io|
    io.read
  end
end

agent = Mechanize.new

# Read in a page
PAGE_URI = URI('http://www.busselton.wa.gov.au')

POLICY_PAGES = [
  '/Council/Policies-Plans/Community-Policies',
  '/Council/Policies-Plans/Governance-and-Administration-Policies'
]
POLICY_PAGES.each do |page_path|
  PAGE_URI.path = page_path
  page = agent.get(PAGE_URI.to_s)

  # get the list of policies
  list = page.search('div.related-information-section > ul > li')

  list.each do |row|
    record = {}
    link = row.search('a')

    record['title'] = link.text

    PAGE_URI.path = link.attr('href')

    record['document_url'] = PAGE_URI.to_s

    if File.basename(PAGE_URI.to_s) =~ /cp(\d+)/
      record['id'] = "cp#{$1}"
    else
      @logger.error PAGE_URI
      exit
    end

    xml_doc = REXML::Document.new(pdftoxml(open(PAGE_URI.to_s)))

    class NoPatternMatch < Exception; end

    date_patterns = [
      /Last.updated.(\d{2})\/(\d{2})\/(\d{4})/,
      /Implemented (\d{2})\/(\d{2})\/(\d{4})/,
      /Last.updated.(.*)/
    ]
     
    date_pattern = date_patterns.shift
 
    begin
      if REXML::XPath.first(xml_doc, "//page/text").text =~ date_pattern
        if $2
          record['last_updated'] = Date.new($3.to_i, $2.to_i, $1.to_i).iso8601
        else
          record['last_updated'] = Date.parse($1).iso8601
        end
      else
        raise NoPatternMatch
      end
    rescue NoPatternMatch
      @logger.info "Could not find date in #{PAGE_URI} using #{date_pattern}"
      if date_pattern = date_patterns.shift
        retry
      else
        @logger.error "Could not find a date in #{PAGE_URI} using any pattern"
      end
    end

    @logger.info(record.inspect)

    if (ScraperWiki.select("* from data where `id`='#{record['id']}'").empty? rescue true)
      ScraperWiki.save_sqlite(['id', 'last_updated'], record)
      @logger.info("Stored #{record.inspect}")
    else
      puts "Skipping already saved record " + record['id']
    end
  end
end
