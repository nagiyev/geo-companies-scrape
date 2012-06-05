
# encoding: UTF-8
require 'mechanize'
require 'nokogiri'
require 'scraperwiki'
#KY="27cedd1f8bd73bcfca715cb8eb0500d813e4b5d2" # S
#KY="43672daa5983e218e41281f06f8e28eb207cd4b0" # M
KY="c6cbf833716dc7760eb83507a858e278b5e84264" #A_B


def get_metadata(key, default)
  begin
    ScraperWiki.get_var(key, default, 2)
  rescue Exception => e
    puts "ERROR: #{e.inspect} during get_metadata(#{key}, #{default})"
  end
end
def save_metadata(key, value)
  begin
   ScraperWiki.save_var(key, value)
  rescue Exception => e 
   puts "ERROR: #{e.inspect} during save_metadata(#{key}, #{value})"
   retry
  end
end
def delete_metadata(name)
  begin
   ScraperWiki.sqliteexecute("delete from swvariables where name=?",[name])
   ScraperWiki.commit()
  rescue Exception => e
   puts "ERROR: #{e.inspect} during delete_metadata(#{name})"
   retry
  end
end


class String
  def pretty
    self.gsub(/\s+/,' ').strip
  end
end

def i_text(str,ign)
  ret = []
  if str.kind_of? (Nokogiri::XML::Element)
    tmp = []
    str.children().each{|st|
      tmp << a_text(st)
    } unless str.name =~ /"script"|#{ign}/
    ret << tmp
  elsif str.kind_of? (Nokogiri::XML::NodeSet)
    str.collect().each{|st|
      ret << a_text(st)
    }
  elsif str.kind_of? (Nokogiri::XML::Text)
    ret << s_text(str)
  end
  return ret.flatten
end

def a_text(str)
  ret = []
  if str.kind_of? (Nokogiri::XML::Element)
    tmp = []
    str.children().each{|st|
      tmp << a_text(st)
    } unless str.name == "script"
    ret << tmp
  elsif str.kind_of? (Nokogiri::XML::NodeSet)
    str.collect().each{|st|
      ret << a_text(st)
    }
  elsif str.kind_of? (Nokogiri::XML::Text)
    ret << s_text(str)
  end
  return ret.flatten
end

def s_text(str)
  return str.text.strip.gsub(/\u00A0/,' ').pretty
end

def c_text(str,con)
  ret = []
  if str.kind_of? (Nokogiri::XML::Element)
    tmp = []
    str.children().each{|st|
      tmp << c_text(st,con)
    }
    ret << tmp
  elsif str.kind_of? (Nokogiri::XML::NodeSet)
    str.collect().each{|st|
      break if st.name =~ /#{con}/
      ret << c_text(st,con)
    }
  elsif str.kind_of? (Nokogiri::XML::Text)
    ret << s_text(str)
  end
  return ret.flatten
end

def cc_text(str,con)
  ret = []
  if str.kind_of? (Nokogiri::XML::Element)
    tmp = []
    str.children().each{|st|
      break if st.name == con
      tmp << cc_text(st,con)
    }
    ret << tmp
  elsif str.kind_of? (Nokogiri::XML::NodeSet)
    str.collect().each{|st|
      ret << cc_text(st,con)
    }
  elsif str.kind_of? (Nokogiri::XML::Text)
    ret << s_text(str)
  end
  return ret.flatten
end

def r_c_text(str,c)
  ret= []
  b = true
  str.collect{|ss|
    tmp = []
    ss.children().collect{|st|
      t = st.text.gsub(/\u00A0/,'').strip
      b = false if st.name == c
      next if b == true
      tmp << t
    }
    if ss.name == "ul"
      ret << tmp.join(",").pretty
    else
      ret << tmp.join(" ").pretty
    end
  }
  return ret
end
def attributes(t,attr)
  return (t.nil? or t.first.nil? or t.first.attributes.nil? or t.first.attributes[attr].nil?) ? "" : t.first.attributes[attr].value
end


def s_key(str)
  return str.gsub(/\'|â€™|\+/,"").gsub(/\s+/," ").strip.gsub(" ","_").downcase
end

def exists(val,tbl,col)
  begin
    return ScraperWiki.sqliteexecute("select count(*) from #{tbl} where #{col}=?",[val])['data'][0][0]
  rescue Exception => e
    puts [val,e].inspect
    return 0
  end
end

def append_base(uri,surl)
  return nil if surl.nil? or surl.empty? or surl == "/"
  return surl if surl =~ /^http/
  return uri.strip + ("/"+surl.strip).gsub(/(\/)+/,"/").strip
end

def parse(pg,act)
  data = pg.body
  uri = URI.parse(pg.uri.to_s)
  base_uri = "#{uri.scheme}://#{uri.host}"  

  if act == "ranked_concepts"
    doc = Nokogiri::XML(data).xpath(".")
    r = {}
    r["language"] = s_text(doc.xpath(".//language/text()"))
    tmp = []
    doc.xpath(".//concepts/concept").each{|ent|
      tmp << {
        "text" => s_text(ent.xpath("./text/text()")),
        "relevance" => s_text(ent.xpath("./relevance/text()")),
      }
    }
    r["concepts"] = tmp
    return r
  elsif act == "ranked_keywords"
    doc = Nokogiri::XML(data).xpath(".")
    r = {}
    r["language"] = s_text(doc.xpath(".//language/text()"))
    tmp = []
    doc.xpath(".//keywords/keyword").each{|ent|
      tmp << {
        "text" => s_text(ent.xpath("./text/text()")),
        "relevance" => s_text(ent.xpath("./relevance/text()")),
      }
    }
    r["keywords"] = tmp
    return r
  elsif act == "named_entities"
    doc = Nokogiri::XML(data).xpath(".")
    r = {}
    r["language"] = s_text(doc.xpath(".//language/text()"))
    tmp = []
    doc.xpath(".//entities/entity").each{|ent|
      tmp << {
        "relevance" => s_text(ent.xpath("./relevance/text()")),
        "count" => s_text(ent.xpath("./count/text()")),
        "text" => s_text(ent.xpath("./text/text()")),
        "type" => s_text(ent.xpath("./type/text()")),
      }
    }
    r["entities"] =  tmp
    return r
  end
end

def get_analysis(val,col1,col2,tbl)
  begin
    begin
      ScraperWiki.sqliteexecute('delete from '+tbl+' where analysis like \'%"language":""%\' or analysis like \'%"keywords":[]%\' or analysis is null')#or  analysis like \'%"entities":[]%\'')
      ScraperWiki.commit()
      @toggle = 1
    end if @toggle.nil? or @toggle == 0

    return ScraperWiki.sqliteexecute("select #{col2} from #{tbl} where #{col1}=?",[val])['data'].flatten.first
  rescue Exception => e
    puts [e.inspect,e.backtrace].inspect
    return nil
  end
end

def get_by_text(data)
  #puts [@limit_reached,@limit_reached==true].inspect
  return nil unless @limit_reached.nil? if @limit_reached == true
  if data.nil? or data.empty? or data.strip.length < 100
    puts "null / insufficient feed"
    return nil 
  end
  base_uri = "http://access.alchemyapi.com/calls/text/"
  hdrs = {
      "X-Requested-With"=>"XMLHttpRequest",
      "Referer"=>"http://access.alchemyapi.com/demo/entities_int.html",
      "Cookie"=>"__utma=191335290.937107543.1334691427.1334691427.1334691427.1; __utmb=191335290.2.10.1334691427; __utmc=191335290; __utmz=191335290.1334691427.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none)"
  }
  params = {"apikey"=>KY,"text"=>data}
  named_entities = parse(Mechanize.new().post(base_uri+"TextGetRankedNamedEntities",params,hdrs),"named_entities")
  ranked_concepts = parse(Mechanize.new().post(base_uri+"TextGetRankedConcepts?showSourceText=1",params,hdrs),"ranked_concepts")
  pg = Mechanize.new().post(base_uri+"TextGetRankedKeywords?showSourceText=1",params,hdrs)
  ranked_keywords = parse(pg,"ranked_keywords")
  if ranked_keywords["keywords"].nil? or ranked_keywords["keywords"].empty? 
    puts "Invalid analysis results for #{data} - #{data.length} :: #{pg.body}"
    @limit_reached = true if pg.body =~ /limit/i
  end
  return JSON.generate({"named_entities"=>named_entities,"ranked_keywords"=>ranked_keywords,"ranked_concepts"=>ranked_concepts}) #unless ranked_keywords.nil? 
end


def get_by_url(url)
  return nil unless @limit_reached.nil? if @limit_reached == true
  raise "Null value" if url.nil? or url.empty? 
  base_uri = "http://access.alchemyapi.com/calls/url/"
  hdrs = {
      "X-Requested-With"=>"XMLHttpRequest",
      "Referer"=>"http://access.alchemyapi.com/demo/entities_int.html",
      "Cookie"=>"__utma=191335290.937107543.1334691427.1334691427.1334691427.1; __utmb=191335290.2.10.1334691427; __utmc=191335290; __utmz=191335290.1334691427.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none)"
  }
  named_entities = parse(Mechanize.new().get(base_uri+"URLGetRankedNamedEntities?apikey=#{KY}&url=#{url}",[],base_uri,hdrs),"named_entities")
  ranked_concepts = parse(Mechanize.new().get(base_uri+"URLGetRankedConcepts?apikey=#{KY}&url=#{url}",[],base_uri,hdrs),"ranked_concepts")
  pg = Mechanize.new().get(base_uri+"URLGetRankedKeywords?apikey=#{KY}&url=#{url}",[],base_uri,hdrs)
  ranked_keywords = parse(pg,"ranked_keywords")
  if ranked_keywords["keywords"].nil? or ranked_keywords["keywords"].empty?   
    puts "Invalid analysis results for #{url} :: #{pg.body}" 
    @limit_reached = true if pg.body =~ /limit/i
  end
  return JSON.generate({"named_entities"=>named_entities,"ranked_keywords"=>ranked_keywords,"ranked_concepts"=>ranked_concepts}) #unless ranked_keywords.nil? 
end

#puts get_by_url("http://www.lynda.com/Acrobat-9-tutorials/professional-tips-and-tricks/652-2.html").inspect
