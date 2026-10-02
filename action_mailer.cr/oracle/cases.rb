# Oracle cases for ActionMailer (Iteration 5, P0 scope).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<value>". The same case IDs are mirrored 1:1
# in spec/oracle_spec.cr; the Crystal port must reproduce expected.yml
# exactly (captured from actionmailer 8.1.4 + mail 2.9.1, delivery
# method :test).
#
# Structural values only (fields, part types, decoded bodies): raw
# RFC output has random boundaries/Message-IDs, so we diff semantics.

gem "actionmailer", "= 8.1.4"
gem "activesupport", "= 8.1.4"
gem "actionpack", "= 8.1.4"
gem "actionview", "= 8.1.4"
require "action_mailer"

ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true

TEST_MAILER = ActionMailer::Base.delivery_method
class BenchMailer < ActionMailer::Base
  default from: "noreply@example.com"

  def welcome_email(addr)
    mail(to: addr, subject: "Welcome!", body: "WELCOME BODY")
  end

  def plain_email(addr)
    mail(to: addr, subject: "Plain") do |format|
      format.text { "TEXT BODY" }
    end
  end

  def fancy_email(addr)
    mail(to: addr, subject: "Fancy") do |format|
      format.text { "TEXT BODY" }
      format.html { "<p>HTML BODY</p>" }
    end
  end

  def unicode_email(addr)
    mail(to: addr, subject: "Unicode") do |format|
      format.text { "Привет, мир!" }
    end
  end

  def with_attachment(addr)
    attachments["report.txt"] = {mime_type: "text/plain", content: "ATTACH DATA"}
    mail(to: addr, subject: "Attached", body: "SEE ATTACHED")
  end

  def custom_headers(addr)
    headers["X-Bench"] = "yes"
    mail(to: addr, subject: "hdr", body: "HDR BODY")
  end
end

def render(v)
  case v
  when String then v
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

WELCOME = BenchMailer.welcome_email("bob@example.com")
PLAIN   = BenchMailer.plain_email("bob@example.com")
FANCY   = BenchMailer.fancy_email("bob@example.com")
UNI     = BenchMailer.unicode_email("bob@example.com")
ATT     = BenchMailer.with_attachment("bob@example.com")
HDR     = BenchMailer.custom_headers("bob@example.com")

# --- DSL -----------------------------------------------------------
case_run("dsl_from")         { WELCOME.message.from }
case_run("dsl_to")           { WELCOME.message.to }
case_run("dsl_subject")      { WELCOME.message.subject }
case_run("dsl_content_type") { PLAIN.message.content_type }
case_run("dsl_body")         { PLAIN.message.body.decoded }
case_run("dsl_headers")      { HDR.message["X-Bench"].value }
case_run("dsl_delivery_class") { WELCOME.class.name }

# --- delivery (test method) ----------------------------------------
case_run("del_deliveries_size") do
  WELCOME.deliver_now
  BenchMailer.deliveries.size
end
case_run("del_last_subject") { BenchMailer.deliveries.last.subject }
case_run("del_last_to")      { BenchMailer.deliveries.last.to }
case_run("del_now_returns")  { PLAIN.deliver_now.class.name }

# --- multipart ------------------------------------------------------
case_run("mp_multipart")   { FANCY.message.multipart? }
case_run("mp_parts")       { FANCY.message.parts.map(&:content_type) }
case_run("mp_part_bodies") { FANCY.message.parts.map { |p| p.body.decoded } }
case_run("mp_top_ct")      { FANCY.message.mime_type }

# --- unicode body (quoted-printable roundtrip) -----------------------
# single-format mail is not multipart: the body sits on the message
case_run("uni_charset")  { UNI.message.charset }
case_run("uni_decoded")  { UNI.message.body.decoded }
case_run("uni_encoded")  { UNI.message.body.encoded.strip }

# --- attachments -----------------------------------------------------
case_run("att_multipart") { ATT.message.multipart? }
case_run("att_top_ct")    { ATT.message.mime_type }
case_run("att_names")     { ATT.message.attachments.map(&:filename) }
case_run("att_decoded")   { ATT.message.attachments.map(&:decoded) }
case_run("att_cte")       { ATT.message.attachments.map(&:content_transfer_encoding) }
case_run("att_mime")      { ATT.message.attachments.map(&:mime_type) }
