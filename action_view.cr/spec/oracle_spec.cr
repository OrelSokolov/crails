# Oracle spec: the Crystal port must reproduce oracle/expected.yml
# exactly (captured from actionview 8.1.4 via oracle/cases.rb).
# Same case IDs, same expectations, no edits on either side.

require "spec"
require "../src/action_view_cr"

# --- expected.yml loader (values may span multiple lines) ---------
EXPECTED = begin
  hash = {} of String => String
  current_id : String? = nil
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
      current_id = id
    elsif cur = current_id
      hash[cur] = hash[cur] + "\n" + line.chomp
    end
  end
  hash
end

class PostModel
  include ActionView::FormModel

  property id : Int32?
  property title : String
  property body : String
  property published : Bool

  def initialize(@id = nil, @title = "", @body = "", @published = false)
  end

  def form_scope : String
    "post"
  end

  def form_attributes : Hash(String, ActionView::FormValue)
    attrs = {} of String => ActionView::FormValue
    attrs["id"] = @id if @id
    attrs["title"] = @title
    attrs["body"] = @body
    attrs["published"] = @published
    attrs
  end

  def form_persisted? : Bool
    !id.nil?
  end
end

# --- direct helper context ----------------------------------------
class OracleCtx
  include ActionView::Helpers
end

CTX = OracleCtx.new
POST = PostModel.new(id: 7, title: "Hi", body: "Words <b>here</b>", published: true)

# --- template-compiled view ---------------------------------------
class TplView
  include ActionView::Helpers

  getter post : PostModel
  getter post_new : PostModel

  def initialize(@post, @post_new)
  end

  compile_template "tpl_erb_escapes", "#{__DIR__}/fixtures/tpl/erb_escapes.html.erb"
  compile_template "tpl_erb_raw_ok", "#{__DIR__}/fixtures/tpl/erb_raw_ok.html.erb"
  compile_template "tpl_ct_block", "#{__DIR__}/fixtures/tpl/ct_block.html.erb"
  compile_template "tpl_ct_nested", "#{__DIR__}/fixtures/tpl/ct_nested.html.erb"
  compile_template "tpl_cycle", "#{__DIR__}/fixtures/tpl/cycle.html.erb"
  compile_template "tpl_current_cycle", "#{__DIR__}/fixtures/tpl/current_cycle.html.erb"
  compile_template "tpl_reset_cycle", "#{__DIR__}/fixtures/tpl/reset_cycle.html.erb"
  compile_template "tpl_link_block", "#{__DIR__}/fixtures/tpl/link_block.html.erb"
  compile_template "tpl_form_tag", "#{__DIR__}/fixtures/tpl/form_tag.html.erb"
  compile_template "tpl_form_tag_method", "#{__DIR__}/fixtures/tpl/form_tag_method.html.erb"
  compile_template "tpl_fw_url", "#{__DIR__}/fixtures/tpl/fw_url.html.erb"
  compile_template "tpl_fw_model_new", "#{__DIR__}/fixtures/tpl/fw_model_new.html.erb"
  compile_template "tpl_fw_model", "#{__DIR__}/fixtures/tpl/fw_model.html.erb"
  compile_template "tpl_fw_label", "#{__DIR__}/fixtures/tpl/fw_label.html.erb"
  compile_template "tpl_fw_fields", "#{__DIR__}/fixtures/tpl/fw_fields.html.erb"
  compile_template "tpl_fw_field_name", "#{__DIR__}/fixtures/tpl/fw_field_name.html.erb"
  compile_template "tpl_content_for", "#{__DIR__}/fixtures/tpl/content_for.html.erb"
end

VIEW = TplView.new(POST, PostModel.new(title: "t"))

# --- partial-compiled view ----------------------------------------
class PartialView
  include ActionView::Helpers

  getter post : PostModel
  getter p1 : PostModel
  getter p2 : PostModel

  def initialize(@post, @p1, @p2)
  end

  compile_partials({
    "post" => {path: "#{__DIR__}/fixtures/partials/_post.html.erb", locals: {"post" => PostModel}},
    "row"  => {path: "#{__DIR__}/fixtures/partials/_row.html.erb",  locals: {"post" => PostModel, "post_counter" => Int32}},
    "wrap" => {path: "#{__DIR__}/fixtures/partials/_wrap.html.erb", locals: {"p" => PostModel}},
    "dash" => {path: "#{__DIR__}/fixtures/partials/_dash.html.erb", locals: {} of String => Nil},
  })
end

PV = PartialView.new(POST, PostModel.new(id: 1, title: "One"), PostModel.new(id: 2, title: "Two"))

T = Time.utc(2026, 1, 1, 12, 0, 0)

# id -> rendered result; raise ids would render as "raise:ClassName".
CASES = {
  # --- output safety ---
  "safe_html_safe"     => -> { "<b>hi</b>".html_safe.html_safe?.to_s },
  "safe_plain_not"     => -> { "<b>hi</b>".html_safe?.to_s },
  "safe_escape_once"   => -> { CTX.escape_once("1 &gt; 2 & 3") },
  "safe_raw"           => -> { CTX.raw("<b>x</b>").to_s },
  "safe_raw_html_safe" => -> { CTX.raw("<b>x</b>").html_safe?.to_s },
  "safe_join"          => -> { CTX.safe_join(["a", "<b>b</b>".html_safe, "c"], " | ").to_s },
  "safe_join_escapes"  => -> { CTX.safe_join(["<i>a</i>", "<b>b</b>".html_safe], ",").to_s },
  "tpl_erb_escapes"    => -> { VIEW.tpl_erb_escapes.to_s },
  "tpl_erb_raw_ok"     => -> { VIEW.tpl_erb_raw_ok.to_s },
  # --- tag ---
  "tag_br"              => -> { CTX.tag("br").to_s },
  "tag_img_src"         => -> { CTX.tag("img", src: "x.png", alt: "Pic").to_s },
  "tag_input_bool_true" => -> { CTX.tag("input", type: "checkbox", checked: true).to_s },
  "tag_input_bool_false" => -> { CTX.tag("input", type: "checkbox", checked: false).to_s },
  "tag_nil_value"       => -> { CTX.tag("img", src: nil, alt: "a").to_s },
  "tag_data_nested"     => -> { CTX.tag("div", data: {"remote" => "true", "url" => "/x"}).to_s },
  "tag_aria_nested"     => -> { CTX.tag("div", aria: {"hidden" => "true"}).to_s },
  "tag_escape_values"   => -> { CTX.tag("img", alt: %(a"b&<c)).to_s },
  "tag_dot_form"        => -> { CTX.tag.br.to_s },
  "tag_dot_attrs"       => -> { CTX.tag.input(type: "text", disabled: true).to_s },
  "ct_block"            => -> { VIEW.tpl_ct_block.to_s },
  "ct_inline"           => -> { CTX.content_tag(:p, "hello", class: "x").to_s },
  "ct_nested"           => -> { VIEW.tpl_ct_nested.to_s },
  "ct_escapes"          => -> { CTX.content_tag(:p, "<script>").to_s },
  # --- text ---
  "txt_pluralize_1"     => -> { CTX.pluralize(1, "person") },
  "txt_pluralize_2"     => -> { CTX.pluralize(2, "person") },
  "txt_pluralize_count" => -> { CTX.pluralize(0, "person/plural") },
  "txt_truncate"        => -> { CTX.truncate("The quick brown fox jumps over the lazy dog", length: 20) },
  "txt_truncate_sep"    => -> { CTX.truncate("The quick brown fox jumps over the lazy dog", length: 20, separator: " ") },
  "txt_truncate_short"  => -> { CTX.truncate("short", length: 20) },
  "txt_truncate_escape" => -> { CTX.truncate("a<b>c" * 10, length: 12, escape: false) },
  "txt_excerpt"         => -> { CTX.excerpt("This is an example", "an", radius: 3) },
  "txt_highlight"       => -> { CTX.highlight("This is a beautiful morning", "beautiful") },
  "txt_highlight_multi" => -> { CTX.highlight("a b c", ["a", "c"]) },
  "txt_word_wrap"       => -> { CTX.word_wrap("one two three four five", line_width: 8) },
  "txt_simple_format"   => -> { CTX.simple_format("a\n\nb\n c") },
  "txt_simple_escapes"  => -> { CTX.simple_format("<b>a</b>") },
  "txt_cycle"           => -> { VIEW.tpl_cycle.to_s },
  "txt_current_cycle"   => -> { VIEW.tpl_current_cycle.to_s },
  "txt_reset_cycle"     => -> { VIEW.tpl_reset_cycle.to_s },
  "txt_dotw_words"      => -> { CTX.distance_of_time_in_words(T, Time.utc(2026, 1, 1, 12, 1, 30)) },
  "txt_dotw_hours"      => -> { CTX.distance_of_time_in_words(T, Time.utc(2026, 1, 1, 17, 0, 0)) },
  "txt_dotw_days"       => -> { CTX.distance_of_time_in_words(Time.utc(2026, 1, 1), Time.utc(2026, 1, 9)) },
  "txt_dotw_about_mo"   => -> { CTX.distance_of_time_in_words(Time.utc(2026, 1, 1), Time.utc(2026, 2, 3)) },
  "txt_dotw_seconds"    => -> { CTX.distance_of_time_in_words(T, Time.utc(2026, 1, 1, 12, 0, 25), include_seconds: true) },
  # --- numbers ---
  "num_currency"   => -> { CTX.number_to_currency(1234.5) },
  "num_delimiter"  => -> { CTX.number_with_delimiter(1234567) },
  "num_precision"  => -> { CTX.number_with_precision(3.14159, precision: 3) },
  "num_percentage" => -> { CTX.number_to_percentage(75.5) },
  "num_human_size" => -> { CTX.number_to_human_size(1048576) },
  "num_human"      => -> { CTX.number_to_human(1_500_000) },
  "num_phone"      => -> { CTX.number_to_phone(5551234567) },
  # --- url ---
  "url_link_plain"   => -> { CTX.link_to("Home", "/").to_s },
  "url_link_escapes" => -> { CTX.link_to(%q<a"b>, "/x?y=1").to_s },
  "url_link_attrs"   => -> { CTX.link_to("X", "/x", class: "btn", data: {"turbo" => "false"}).to_s },
  "url_link_block"   => -> { VIEW.tpl_link_block.to_s },
  "url_link_if_true" => -> { CTX.link_to_if(true, "Y", "/y").to_s },
  "url_link_if_false" => -> { CTX.link_to_if(false, "Y", "/y") { "(none)" } },
  "url_link_unless"  => -> { CTX.link_to_unless(false, "Z", "/z").to_s },
  "url_mail_to"      => -> { CTX.mail_to("me@example.com", "Me").to_s },
  "url_mail_to_emails" => -> { CTX.mail_to("me@example.com").to_s },
  "url_button_to"    => -> { CTX.button_to("Go", "/go").to_s },
  "url_button_method" => -> { CTX.button_to("Del", "/d", method: "delete").to_s },
  # --- assets ---
  "asset_css"         => -> { CTX.stylesheet_link_tag("a", "b").to_s },
  "asset_js"          => -> { CTX.javascript_include_tag("a", "b").to_s },
  "asset_image"       => -> { CTX.image_tag("x.png", alt: "X").to_s },
  "asset_image_size"  => -> { CTX.image_tag("x.png", size: "40x50").to_s },
  "asset_favicon"     => -> { CTX.favicon_link_tag.to_s },
  "asset_js_tag"      => -> { CTX.javascript_tag("alert(1)").to_s },
  # --- form tag helpers ---
  "ft_text_field"       => -> { CTX.text_field_tag("name", "val", class: "i").to_s },
  "ft_label"            => -> { CTX.label_tag("name", "Name").to_s },
  "ft_label_only"       => -> { CTX.label_tag("name").to_s },
  "ft_hidden"           => -> { CTX.hidden_field_tag("token", "abc").to_s },
  "ft_password"         => -> { CTX.password_field_tag("pw").to_s },
  "ft_email"            => -> { CTX.email_field_tag("email", "a@b.c").to_s },
  "ft_number"           => -> { CTX.number_field_tag("n", 5, min: 0, max: 10).to_s },
  "ft_date"             => -> { CTX.date_field_tag("d", "2026-01-02").to_s },
  "ft_check"            => -> { CTX.check_box_tag("ok", "1", true).to_s },
  "ft_check_false"      => -> { CTX.check_box_tag("ok", "1", false).to_s },
  "ft_radio"            => -> { CTX.radio_button_tag("g", "f", true).to_s },
  "ft_text_area"        => -> { CTX.text_area_tag("body", "hi", rows: 3).to_s },
  "ft_search"           => -> { CTX.search_field_tag("q", "x").to_s },
  "ft_tel"              => -> { CTX.telephone_field_tag("p", "123").to_s },
  "ft_url_field"        => -> { CTX.url_field_tag("u", "https://x.y").to_s },
  "ft_color"            => -> { CTX.color_field_tag("c", "#ffffff").to_s },
  "ft_range"            => -> { CTX.range_field_tag("r", 3, min: 0, max: 9).to_s },
  "ft_submit"           => -> { CTX.submit_tag("Save", class: "b").to_s },
  "ft_button"           => -> { CTX.button_tag("Cancel").to_s },
  "ft_button_value"     => -> { CTX.button_tag("Ok", value: "confirm").to_s },
  "ft_select"           => -> { CTX.select_tag("t", CTX.options_for_select([{"A", 1}, {"B", 2}], 2)).to_s },
  "ft_select_prompt"    => -> { CTX.select_tag("t", CTX.options_for_select([{"A", 1}]), prompt: "Pick").to_s },
  "ft_select_multiple"  => -> { CTX.select_tag("t", CTX.options_for_select([{"A", 1}, {"B", 2}]), multiple: true).to_s },
  "ft_options_selected" => -> { CTX.options_for_select(["a", "b"], "a").to_s },
  "ft_form_tag"         => -> { VIEW.tpl_form_tag.to_s },
  "ft_form_tag_method"  => -> { VIEW.tpl_form_tag_method.to_s },
  # --- form_with / FormBuilder ---
  "fw_url"         => -> { VIEW.tpl_fw_url.to_s },
  "fw_model_new"   => -> { VIEW.tpl_fw_model_new.to_s },
  "fw_model"       => -> { VIEW.tpl_fw_model.to_s },
  "fw_label"       => -> { VIEW.tpl_fw_label.to_s },
  "fw_fields"      => -> { VIEW.tpl_fw_fields.to_s },
  "fw_field_name"  => -> { VIEW.tpl_fw_field_name.to_s },
  # --- capture ---
  "cap_content_for" => -> { VIEW.tpl_content_for.to_s },
  # --- partials ---
  "prt_locals"           => -> { PV.render(partial: "post", locals: {"post" => PV.post}).to_s },
  "prt_collection"       => -> { PV.render(partial: "post", collection: [PV.p1, PV.p2]).to_s },
  "prt_collection_empty" => -> { PV.render(partial: "post", collection: [] of PostModel).to_s },
  "prt_collection_as"    => -> { PV.render(partial: "row", collection: [PV.p1, PV.p2], as_local: "post").to_s },
  "prt_nested"           => -> { PV.render(partial: "wrap", locals: {"p" => PV.post}).to_s },
  "prt_spacer"           => -> { PV.render(partial: "post", collection: [PV.p1, PV.p2], spacer_template: "dash").to_s },
}

describe "action_view oracle (actionview 8.1.4)" do
  EXPECTED.each do |id, expected|
    it id do
      block = CASES[id]?
      block.should_not be_nil, "case #{id} not mirrored in spec"
      result = block.not_nil!.call.to_s
      result.strip.should eq(expected.strip), <<-MSG
        #{id}:
          expected: #{expected.inspect}
          got:      #{result.inspect}
        MSG
    end
  end

  it "mirrors every oracle case" do
    missing = EXPECTED.keys - CASES.keys
    extra = CASES.keys - EXPECTED.keys
    missing.should be_empty
    extra.should be_empty
  end

  it "content_for stores content for the layout" do
    VIEW.tpl_content_for.to_s # run once to fill :sidebar
    VIEW.content_for(:sidebar).to_s.should eq("S")
    VIEW.content_for?(:sidebar).should be_true
  end
end
