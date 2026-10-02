# MailDeliveryJob — the ActiveJob bridge for deliver_later, mirroring
# Rails 8.1: arguments are [mailer_class_name, action, delivery_method,
# {"args" => [...], "_aj_ruby2_keywords" => ["args"]}], queue :mailers.

module ActionMailer
  class MailDeliveryJob < ActiveJob::Base
    def perform(mailer_name, action, delivery_method, params)
      klass = ActionMailer.lookup_mailer(mailer_name.as(String))
      raise ArgumentError.new("Unknown mailer: #{mailer_name}") unless klass

      args = if (a = params.as(Hash(String | Symbol, ActiveJob::ArgValue))["args"]?).nil?
               [] of ActiveJob::ArgValue
             else
               a.as(Array(ActiveJob::ArgValue))
             end

      msg = klass.__deliver(action.as(String), args)
      case delivery_method.as(String)
      when "deliver_now!"
        Base.deliver(msg) # bang variant skips callbacks (none in P0)
      else
        Base.deliver(msg)
      end
      nil
    end
  end
end
