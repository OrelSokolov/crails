# action_mailer_cr — Crystal port of ActionMailer 8.1.4 (Iteration 5,
# P0: DSL + mail-core + :test delivery + minimal SMTP client).
require "base64"
require "active_support_cr"
require "./mail"
require "./base"
require "./rfc2822"
require "./smtp"

module ActionMailer
  def self.deliveries : Array(Mail::Message)
    Base.deliveries
  end
end
