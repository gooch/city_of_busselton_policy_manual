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

  command = ['/usr/bin/pdftohtml', '-xml', '-f', 1, '-t', 1, '-nodrm', '-zoom', '1.5', '-enc', 'UTF-8', '-noframes', '-stdout', src.path]
 
  IO.popen(command, :err => [:child, :out]) do |io|
    io.read
  end
end

def open_cached_or_remote(uri)
  FileUtils.mkdir('policies') unless File.exist?('policies')

  filename = File.join('policies', File.basename(uri.to_s))

  begin
    return open(filename, 'r')
  rescue Errno::ENOENT
    system 'wget', '-O', filename, uri.to_s
    retry
  end
end

agent = Mechanize.new

# Read in a page
PAGE_URI = URI('http://www.busselton.wa.gov.au')

PAGE_URI.path = '/Council/Policies-Plans/Community-Policies'

page = agent.get(PAGE_URI.to_s)

# get the list of policies
list = page.search('div.related-information-section > ul > li')

list.each do |row|
  record = {}
  link = row.search('a')

  record['title'] = link.text

  PAGE_URI.path = link.attr('href')

  record['document_url'] = PAGE_URI.to_s

  if File.basename(PAGE_URI.to_s) =~ /cp_(\d+)/
    record['id'] = "cp_#{$1}"
  end

  xml_doc = REXML::Document.new(pdftoxml(open_cached_or_remote(PAGE_URI.to_s)))
  # puts xml_doc.xpath("//text[contains('Last updated')]")
  begin
    if REXML::XPath.first(xml_doc, "//page/text").text =~ /Last updated (.*)/
      record['last_updated'] = Date.parse($1).iso8601
    elsif REXML::XPath.first(xml_doc, "//page/text").text =~ /Implemented (.*)/
      record['last_updated'] = Date.parse($1).iso8601
    end
  rescue NoMethodError
    @logger.warn "Could not find date in #{PAGE_URI}"
  end

  @logger.info(record.inspect)

  if (ScraperWiki.select("* from data where `id`='#{record['id']}'").empty? rescue true)
    ScraperWiki.save_sqlite(['id'], record)
    @logger.info("Stored #{record.inspect}")
  else
    puts "Skipping already saved record " + record['id']
  end
end
