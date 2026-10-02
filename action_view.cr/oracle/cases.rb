# Synthetic oracle cases for ActionView P0/P1 (Iteration 3).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<rendered HTML>". The same case IDs are
# mirrored 1:1 in spec/oracle_spec.cr; the Crystal port must reproduce
# expected.yml exactly (captured from actionview 8.1.4).
#
# Block/output-buffer helpers (form_with, content_tag with block,
# content_for) are exercised through standalone inline ERB rendering,
# exactly like a real template would run them.
gem "actionview", "= 8.1.4"
require "action_view"
require "active_model"

def render(v)
  case v
  when String then v
  when true, false, Integer, Float, nil then v.inspect
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

# Standalone view: renders inline ERB templates the way a real request
# does (output buffer, capture, block helpers). CSRF protection is off
# (no controller/session here) — matches the CRails port, which has no
# CSRF layer yet; both sides generate identical tokenless forms.
class OracleView < ActionView::Base
  def protect_against_forgery?; false; end
end
VIEW = OracleView.with_empty_template_cache.new(ActionView::LookupContext.new([]), {}, nil)

# Plain helper context for direct (non-template) calls.
class Ctx
  include ActionView::Helpers
  def protect_against_forgery?; false; end
  def output_buffer; @output_buffer ||= nil; end
  attr_writer :output_buffer
end
CTX = Ctx.new

def tpl(src)
  VIEW.render(inline: src, formats: [:html]).strip
end

# Top-level delegation so case bodies can call helpers bare.
%w[
  escape_once raw safe_join content_tag tag
  pluralize truncate excerpt highlight word_wrap simple_format
  distance_of_time_in_words time_ago_in_words
  number_to_currency number_with_delimiter number_with_precision
  number_to_percentage number_to_human_size number_to_human number_to_phone
  link_to link_to_if link_to_unless mail_to button_to
  stylesheet_link_tag javascript_include_tag image_tag favicon_link_tag
  javascript_tag
  text_field_tag label_tag hidden_field_tag password_field_tag
  email_field_tag number_field_tag date_field_tag check_box_tag
  radio_button_tag text_area_tag search_field_tag telephone_field_tag
  url_field_tag color_field_tag range_field_tag submit_tag button_tag
  select_tag options_for_select
].each do |m|
  define_method(m) { |*a, **k, &b| CTX.public_send(m, *a, **k, &b) }
end

class PostModel
  include ActiveModel::Model
  attr_accessor :id, :title, :body, :published
  def self.model_name
    ActiveModel::Name.new(self, nil, "Post")
  end
  def to_param; id.to_s; end
  def persisted?; !id.nil?; end
end

# --- Output safety ------------------------------------------------
case_run("safe_html_safe")      { "<b>hi</b>".html_safe.html_safe? }
case_run("safe_plain_not")      { "<b>hi</b>".html_safe? }
case_run("safe_escape_once")    { escape_once("1 &gt; 2 & 3") }
case_run("safe_raw")            { raw("<b>x</b>") }
case_run("safe_raw_html_safe")  { raw("<b>x</b>").html_safe? }
case_run("safe_join")           { safe_join(["a", "<b>b</b>".html_safe, "c"], " | ") }
case_run("safe_join_escapes")   { safe_join(["<i>a</i>", "<b>b</b>".html_safe], ",") }
case_run("tpl_erb_escapes")     { tpl(%q{<%= "<script>x</script>" %>}) }
case_run("tpl_erb_raw_ok")      { tpl(%q{<%= raw "<b>ok</b>" %>}) }

# --- TagHelper ----------------------------------------------------
case_run("tag_br")              { tag("br") }
case_run("tag_img_src")         { tag("img", src: "x.png", alt: "Pic") }
case_run("tag_input_bool_true") { tag("input", type: "checkbox", checked: true) }
case_run("tag_input_bool_false"){ tag("input", type: "checkbox", checked: false) }
case_run("tag_nil_value")       { tag("img", src: nil, alt: "a") }
case_run("tag_data_nested")     { tag("div", data: {remote: "true", url: "/x"}) }
case_run("tag_aria_nested")     { tag("div", aria: {hidden: "true"}) }
case_run("tag_escape_values")   { tag("img", alt: %(a"b&<c)) }
case_run("tag_dot_form")        { tag.br }
case_run("tag_dot_attrs")       { tag.input type: "text", disabled: true }
case_run("ct_block")            { tpl(%q{<%= content_tag(:div, class: "wrap") { "inner" } %>}) }
case_run("ct_inline")           { content_tag(:p, "hello", class: "x") }
case_run("ct_nested")           { tpl(%q{<%= content_tag(:ul) { safe_join([content_tag(:li, "1"), content_tag(:li, "2")]) } %>}) }
case_run("ct_escapes")          { content_tag(:p, "<script>") }

# --- TextHelper ---------------------------------------------------
case_run("txt_pluralize_1")     { pluralize(1, "person") }
case_run("txt_pluralize_2")     { pluralize(2, "person") }
case_run("txt_pluralize_count") { pluralize(0, "person/plural") }
case_run("txt_truncate")        { truncate("The quick brown fox jumps over the lazy dog", length: 20) }
case_run("txt_truncate_sep")    { truncate("The quick brown fox jumps over the lazy dog", length: 20, separator: " ") }
case_run("txt_truncate_short")  { truncate("short", length: 20) }
case_run("txt_truncate_escape") { truncate("a<b>c" * 10, length: 12, escape: false) }
case_run("txt_excerpt")         { excerpt("This is an example", "an", radius: 3) }
case_run("txt_highlight")       { highlight("This is a beautiful morning", "beautiful") }
case_run("txt_highlight_multi") { highlight("a b c", ["a", "c"]) }
case_run("txt_word_wrap")       { word_wrap("one two three four five", line_width: 8) }
case_run("txt_simple_format")   { simple_format("a\n\nb\n c") }
case_run("txt_simple_escapes")  { simple_format("<b>a</b>") }
case_run("txt_cycle")           { tpl(%q{<%= cycle("a", "b") %><%= cycle("a", "b") %><%= cycle("a", "b") %>}) }
case_run("txt_current_cycle")   { tpl(%q{<% cycle("x", "y") %><%= current_cycle %>}) }
case_run("txt_reset_cycle")     { tpl(%q{<% cycle("x", "y") %><% reset_cycle %><%= cycle("x", "y") %>}) }
case_run("txt_dotw_words")      { distance_of_time_in_words(Time.utc(2026,1,1,12,0,0), Time.utc(2026,1,1,12,1,30)) }
case_run("txt_dotw_hours")      { distance_of_time_in_words(Time.utc(2026,1,1,12,0,0), Time.utc(2026,1,1,17,0,0)) }
case_run("txt_dotw_days")       { distance_of_time_in_words(Time.utc(2026,1,1), Time.utc(2026,1,9)) }
case_run("txt_dotw_about_mo")   { distance_of_time_in_words(Time.utc(2026,1,1), Time.utc(2026,2,3)) }
case_run("txt_dotw_seconds")    { distance_of_time_in_words(Time.utc(2026,1,1,12,0,0), Time.utc(2026,1,1,12,0,25), include_seconds: true) }

# --- NumberHelper (re-exported from ActiveSupport) ----------------
case_run("num_currency")        { number_to_currency(1234.5) }
case_run("num_delimiter")       { number_with_delimiter(1234567) }
case_run("num_precision")       { number_with_precision(3.14159, precision: 3) }
case_run("num_percentage")      { number_to_percentage(75.5) }
case_run("num_human_size")      { number_to_human_size(1048576) }
case_run("num_human")           { number_to_human(1_500_000) }
case_run("num_phone")           { number_to_phone(5551234567) }

# --- UrlHelper ----------------------------------------------------
case_run("url_link_plain")      { link_to("Home", "/") }
case_run("url_link_escapes")    { link_to(%q<a"b>, "/x?y=1") }
case_run("url_link_attrs")      { link_to("X", "/x", class: "btn", data: {turbo: "false"}) }
case_run("url_link_block")      { tpl(%q{<%= link_to "/x" do %>Big <b>link</b><% end %>}) }
case_run("url_link_if_true")    { link_to_if(true, "Y", "/y") }
case_run("url_link_if_false")   { link_to_if(false, "Y", "/y") { "(none)" } }
case_run("url_link_unless")     { link_to_unless(false, "Z", "/z") }
case_run("url_mail_to")         { mail_to("me@example.com", "Me") }
case_run("url_mail_to_emails")  { mail_to("me@example.com") }
case_run("url_button_to")       { button_to("Go", "/go") }
case_run("url_button_method")   { button_to("Del", "/d", method: :delete) }

# --- AssetTagHelper ----------------------------------------------
case_run("asset_css")           { stylesheet_link_tag("a", "b") }
case_run("asset_js")            { javascript_include_tag("a", "b") }
case_run("asset_image")         { image_tag("x.png", alt: "X") }
case_run("asset_image_size")    { image_tag("x.png", size: "40x50") }
case_run("asset_favicon")       { favicon_link_tag }
case_run("asset_js_tag")        { javascript_tag("alert(1)") }

# --- FormTagHelper -----------------------------------------------
case_run("ft_text_field")       { text_field_tag("name", "val", class: "i") }
case_run("ft_label")            { label_tag("name", "Name") }
case_run("ft_label_only")       { label_tag("name") }
case_run("ft_hidden")           { hidden_field_tag("token", "abc") }
case_run("ft_password")         { password_field_tag("pw") }
case_run("ft_email")            { email_field_tag("email", "a@b.c") }
case_run("ft_number")           { number_field_tag("n", 5, min: 0, max: 10) }
case_run("ft_date")             { date_field_tag("d", "2026-01-02") }
case_run("ft_check")            { check_box_tag("ok", "1", true) }
case_run("ft_check_false")      { check_box_tag("ok", "1", false) }
case_run("ft_radio")            { radio_button_tag("g", "f", true) }
case_run("ft_text_area")        { text_area_tag("body", "hi", rows: 3) }
case_run("ft_search")           { search_field_tag("q", "x") }
case_run("ft_tel")              { telephone_field_tag("p", "123") }
case_run("ft_url_field")        { url_field_tag("u", "https://x.y") }
case_run("ft_color")            { color_field_tag("c", "#ffffff") }
case_run("ft_range")            { range_field_tag("r", 3, min: 0, max: 9) }
case_run("ft_submit")           { submit_tag("Save", class: "b") }
case_run("ft_button")           { button_tag("Cancel") }
case_run("ft_button_value")     { button_tag("Ok", value: "confirm") }
case_run("ft_select")           { select_tag("t", options_for_select([["A", 1], ["B", 2]], 2)) }
case_run("ft_select_prompt")    { select_tag("t", options_for_select([["A", 1]]), prompt: "Pick") }
case_run("ft_select_multiple")  { select_tag("t", options_for_select([["A", 1], ["B", 2]]), multiple: true) }
case_run("ft_options_selected") { options_for_select(%w[a b], "a") }
case_run("ft_form_tag")         { tpl(%q{<%= form_tag "/posts" do %>x<% end %>}) }
case_run("ft_form_tag_method")  { tpl(%q{<%= form_tag "/p", method: :patch do %>x<% end %>}) }

# --- FormHelper / FormBuilder ------------------------------------
POST = PostModel.new(id: 7, title: "Hi", body: "Words <b>here</b>", published: true)

case_run("fw_url")              { tpl(%q{<%= form_with url: "/x" do |f| %>B<% end %>}) }
case_run("fw_model_new")        { tpl(%q{<%= form_with model: PostModel.new(id: nil, title: "t"), url: "/posts" do |f| %><%= f.text_field :title %><% end %>}) }
case_run("fw_model")            { tpl(%q{<%= form_with model: POST, url: "/posts" do |f| %><%= f.text_field :title %><%= f.text_area :body %><%= f.check_box :published %><%= f.submit "Go" %><% end %>}) }
case_run("fw_label")            { tpl(%q{<%= form_with model: POST, url: "/posts" do |f| %><%= f.label :title %><% end %>}) }
case_run("fw_fields")           { tpl(%q{<%= form_with model: POST, url: "/posts" do |f| %><%= f.hidden_field :id %><% end %>}) }
case_run("fw_field_name")       { tpl(%q{<%= form_with model: POST, url: "/posts" do |f| %><%= f.field_name(:title) %><% end %>}) }

# --- Partials (on-disk fixtures in oracle/fixtures) ---------------
# A second standalone view whose lookup paths point at the fixtures
# dir, so partials resolve from disk exactly like a real app.
PVIEW = OracleView.with_empty_template_cache.new(
  ActionView::LookupContext.new([File.expand_path("fixtures", __dir__)]), {}, nil
)
P1 = PostModel.new(id: 1, title: "One")
P2 = PostModel.new(id: 2, title: "Two")

case_run("prt_locals") do
  PVIEW.render(partial: "post", locals: {post: POST}).strip
end
case_run("prt_collection") do
  PVIEW.render(partial: "post", collection: [P1, P2]).strip
end
case_run("prt_collection_empty") do
  # Rails returns nil for an empty collection; through a template the
  # rendered output is "" — compare at the template level.
  PVIEW.render(inline: %q{<%= render partial: "post", collection: [] %>}, formats: [:html]).strip
end
case_run("prt_collection_as") do
  PVIEW.render(partial: "row", collection: [P1, P2], as: :post).strip
end
case_run("prt_nested") do
  PVIEW.render(partial: "wrap", locals: {p: POST}).strip
end
case_run("prt_spacer") do
  PVIEW.render(partial: "post", collection: [P1, P2], spacer_template: "dash").strip
end

# --- CaptureHelper / content_for (via layout) --------------------
case_run("cap_content_for")     { tpl(%q{<% content_for :sidebar do %>S<% end %>B}) }
