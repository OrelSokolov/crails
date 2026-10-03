# Oracle spec: the Crystal port must reproduce oracle/expected.yml
# exactly (captured from actiontext 8.1.4 via oracle/cases.rb: Nokogiri
# HTML5 fragments, libxml2 safe-list sanitizer, SQLite in-memory
# fixtures, Disk service for the embeds association). Same case IDs,
# no edits. Values are escaped with the same \n/\t protocol the oracle
# writer uses.

require "spec"
require "../src/action_text_cr"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

def escape(s : String) : String
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

TEST_URL = ENV["AT_TEST_URL"]? ||
           "postgres://root@/crails_as_test?host=/var/run/postgresql"

ActiveRecord::Base.establish_connection(TEST_URL)

# Clean tables between runs (oracle used a fresh in-memory DB).
ActiveRecord::Base.connection.exec("DELETE FROM action_text_rich_texts")
ActiveRecord::Base.connection.exec("DELETE FROM messages")

class Message < ActiveRecord::Base
  has_rich_text :content
end

CONTENT = ActionText::Content

CASES = {
  # --- Content: HTML serialization ---
  "html_h1"      => -> { CONTENT.new("<h1>Funny times!</h1>").to_html },
  "html_script"  => -> { CONTENT.new(%q(<div onclick='action()'>safe<script>unsafe()</script></div>)).to_html },
  "html_br"      => -> { CONTENT.new("line1<br>line2").to_html },
  "html_entity"  => -> { CONTENT.new("&lt;script&gt;alert()&lt;/script&gt;").to_html },
  "html_empty"   => -> { CONTENT.new("").to_html },
  "html_strip"   => -> { CONTENT.new("   <p>x</p>   ").to_html },
  "html_list"    => -> { CONTENT.new("<ul><li>one</li><li>two</li></ul>").to_html },
  "html_inline"  => -> { CONTENT.new("<strong>bold</strong> and <em>it</em>").to_html },
  "html_newline" => -> { CONTENT.new("<h1>a</h1>\n<p>b</p>").to_html },
  # --- Content: to_plain_text ---
  "pt_h1"         => -> { CONTENT.new("<h1>Funny times!</h1>").to_plain_text },
  "pt_div_script" => -> { CONTENT.new(%q(<div onclick='action()'>safe<script>unsafe()</script></div>)).to_plain_text },
  "pt_blocks"     => -> { CONTENT.new("<h1>T</h1><p>P</p>").to_plain_text },
  "pt_divs"       => -> { CONTENT.new("<div>d1</div><div>d2</div>").to_plain_text },
  "pt_br"         => -> { CONTENT.new("a<br>b").to_plain_text },
  "pt_ul"         => -> { CONTENT.new("<ul><li>one</li><li>two</li></ul>").to_plain_text },
  "pt_ol"         => -> { CONTENT.new("<ol><li>a</li><li>b</li></ol>").to_plain_text },
  "pt_nested_ul"  => -> { CONTENT.new("<ul><li>a<ul><li>b</li></ul></li></ul>").to_plain_text },
  "pt_blockquote" => -> { CONTENT.new("<blockquote>quoted</blockquote>").to_plain_text },
  "pt_bq_empty"   => -> { CONTENT.new("<blockquote></blockquote>").to_plain_text },
  "pt_figcaption" => -> { CONTENT.new("<figure><figcaption>cap</figcaption></figure>").to_plain_text },
  "pt_entity"     => -> { CONTENT.new("&lt;script&gt;alert()&lt;/script&gt;").to_plain_text },
  "pt_style"      => -> { CONTENT.new("<style>.x{color:red}</style>text").to_plain_text },
  "pt_mixed"      => -> { CONTENT.new("<h1>Doc</h1><div>line</div>tail").to_plain_text },
  "pt_empty"      => -> { CONTENT.new("").to_plain_text },
  # --- Content: links ---
  "links_basic" => -> { CONTENT.new(%(<a href="http://example.com/">E</a>)).links.inspect },
  "links_uniq"  => -> { CONTENT.new(%(<a href="http://a.io/">1</a><a href="http://a.io/">2</a><a href="https://b.io/x">3</a>)).links.inspect },
  "links_none"  => -> { CONTENT.new("<p>no links</p>").links.inspect },
  # --- sanitize (what to_s renders inside the layout) ---
  "sz_script"  => -> { ActionText::Sanitizer.sanitize(CONTENT.new(%q(<div onclick='action()'>safe<script>unsafe()</script></div>)).to_html) },
  "sz_kept"    => -> { ActionText::Sanitizer.sanitize(CONTENT.new("<h1>Keep</h1><b>b</b>").to_html) },
  "sz_bad_tag" => -> { ActionText::Sanitizer.sanitize(CONTENT.new("<custom>x</custom>y").to_html) },
  "sz_href"    => -> { ActionText::Sanitizer.sanitize(CONTENT.new(%(<a href="http://e.com/" onclick="steal()">L</a>)).to_html) },
  # --- serialization ---
  "ser_dump"      => -> { CONTENT.dump(CONTENT.new("<b>x</b>")).to_s },
  "ser_dump_nil"  => -> { CONTENT.dump(nil).inspect },
  "ser_load"      => -> { CONTENT.load("<b>x</b>").not_nil!.to_html },
  "ser_load_nil"  => -> { CONTENT.load(nil).inspect },
  "ser_roundtrip" => -> { CONTENT.load(CONTENT.dump(CONTENT.new("<p>r</p>"))).not_nil!.to_plain_text },
}

MSG = Message.create!({"content" => "<h1>Funny times!</h1>"})

RT_CASES = {
  "rt_plain"      => -> { MSG.content.to_plain_text },
  "rt_present"    => -> { MSG.content?.to_s },
  "rt_row"        => -> {
    row = ActionText::RichText.where({"record_type" => "Message", "record_id" => MSG.id.not_nil!}).first.not_nil!
    [row.name, row.record_type, row.record_id == MSG.id, row.body].inspect
  },
  "rt_body_db"    => -> { ActiveRecord::Base.connection.scalar("SELECT body FROM action_text_rich_texts").to_s },
  "rt_reload"     => -> { Message.find(MSG.id.not_nil!).not_nil!.content.to_plain_text },
  "rt_update"     => -> {
    m = Message.find(MSG.id.not_nil!).not_nil!
    m.content = "Updated <b>bold</b>"
    m.save!
    [Message.find(MSG.id.not_nil!).not_nil!.content.to_plain_text,
     ActionText::RichText.count(record_type: "Message")].inspect
  },
  "rt_absent"     => -> { Message.create!.content?.to_s },
  "rt_blank_body" => -> { Message.create!({"content" => ""}).content?.to_s },
  "rt_entity"     => -> { Message.create!({"content" => "&lt;script&gt;alert()&lt;/script&gt;"}).content.to_plain_text },
  "rt_to_s"       => -> { Message.create!({"content" => "<h1>Funny times!</h1>"}).content.to_s },
  "rt_to_s_div"   => -> { Message.create!({"content" => "<div>d</div>"}).content.to_s },
  "rt_to_s_san"   => -> { Message.create!({"content" => %q(<div onclick='a()'>safe<script>u()</script></div>)}).content.to_s },
}

describe "action_text oracle" do
  CASES.each do |id, block|
    it id do
      expected = EXPECTED[id]? || fail("missing expected value for #{id}")
      escape(block.call).should eq expected
    end
  end

  RT_CASES.each do |id, block|
    it id do
      expected = EXPECTED[id]? || fail("missing expected value for #{id}")
      escape(block.call).should eq expected
    end
  end
end
