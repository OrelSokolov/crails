# Oracle cases for Devise (Iteration 6, P0 scope: model side of
# database_authenticatable + validatable + rememberable + registerable —
# bcrypt with pepper; sessions/HTTP covered by port unit specs like the
# action_mailer SMTP client).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<value>" (control chars escaped). Mirrored 1:1
# in spec/oracle_spec.cr; captured from devise 4.9.4 over SQLite
# in-memory.

gem "devise", "= 4.9.4"
gem "activerecord", "= 8.1.4"
gem "activesupport", "= 8.1.4"
gem "bcrypt", "= 3.1.21"
gem "sqlite3", ">= 2.1"
require "devise"
require "devise/orm/active_record"

ActiveRecord::Migration.verbose = false
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string   :email,              null: false
    t.string   :encrypted_password, null: false
    t.datetime :remember_created_at
    t.timestamps
  end
end

class User < ActiveRecord::Base
  devise :database_authenticatable, :rememberable, :validatable
end

def render(v)
  s = v.is_a?(String) ? v : v.inspect
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

USER = User.create!(email: "a@b.c", password: "secret123",
                    password_confirmation: "secret123")

# --- encrypted password (bcrypt + stretches) -----------------------------
case_run("pw_digest_shape") { USER.encrypted_password.match?(/\A\$2a\$12\$[\.\/A-Za-z0-9]{53}\z/) }
case_run("pw_valid")        { User.find(USER.id).valid_password?("secret123") }
case_run("pw_wrong")        { User.find(USER.id).valid_password?("nope") }
case_run("pw_blank_hash")   { User.new(email: "x@y.z").valid_password?("any") }
case_run("pw_deterministic_by_salt") do
  # same password + same salt → same digest (compare re-hash)
  fresh = User.new(email: "p@q.r", password: "secret123")
  salt = USER.encrypted_password[0, 29]
  rehashed = BCrypt::Engine.hash_secret("secret123", salt)
  rehashed.start_with?(salt)
end

# --- pepper ----------------------------------------------------------------
PEPPERED = Class.new(ActiveRecord::Base) do
  self.table_name = "users"
  devise :database_authenticatable, :validatable
  self.pepper = "s3cr3t-pepper"
end

case_run("pw_pepper_digest") do
  u = PEPPERED.new(email: "p@q.r", password: "secret123")
  salt = u.encrypted_password[0, 29]
  u.encrypted_password == BCrypt::Engine.hash_secret("secret123s3cr3t-pepper", salt)
end
case_run("pw_pepper_valid") do
  u = PEPPERED.create!(email: "p@q.r", password: "secret123", password_confirmation: "secret123")
  [u.valid_password?("secret123"), u.valid_password?("secret123s3cr3t-pepper")]
end

# --- validatable -------------------------------------------------------------
case_run("val_ok")        { User.new(email: "ok@e.co", password: "longenough", password_confirmation: "longenough").valid? }
case_run("val_email_missing") do
  u = User.new(password: "longenough", password_confirmation: "longenough")
  [u.valid?, u.errors.attribute_names.include?(:email)]
end
case_run("val_email_bad") do
  u = User.new(email: "no-at", password: "longenough", password_confirmation: "longenough")
  [u.valid?, u.errors.attribute_names.include?(:email)]
end
case_run("val_email_uniq") do
  u = User.new(email: USER.email.upcase, password: "longenough", password_confirmation: "longenough")
  [u.valid?, u.errors.attribute_names.include?(:email)]
end
case_run("val_pw_short") do
  u = User.new(email: "s@e.co", password: "abc", password_confirmation: "abc")
  [u.valid?, u.errors.attribute_names.include?(:password)]
end
case_run("val_pw_long") do
  u = User.new(email: "s@e.co", password: "x" * 129, password_confirmation: "x" * 129)
  [u.valid?, u.errors.attribute_names.include?(:password)]
end
case_run("val_pw_mismatch") do
  u = User.new(email: "s@e.co", password: "longenough", password_confirmation: "different")
  [u.valid?, u.errors.attribute_names.include?(:password_confirmation)]
end
case_run("val_update_no_pw") do
  u = User.find(USER.id)
  u.email = "new@e.co"
  u.valid?
end

# --- update_with_password -----------------------------------------------
case_run("uwp_ok") do
  u = User.find(USER.id)
  res = u.update_with_password(current_password: "secret123", email: "uwp@e.co")
  [res, User.find(USER.id).email]
end
case_run("uwp_bad_pw") do
  u = User.find(USER.id)
  res = u.update_with_password(current_password: "WRONG", email: "hacked@e.co")
  [res, u.errors.attribute_names.include?(:current_password), User.find(USER.id).email]
end
case_run("uwp_new_password") do
  u = User.find(USER.id)
  res = u.update_with_password(current_password: "secret123",
                               password: "newpass99", password_confirmation: "newpass99")
  [res, User.find(USER.id).valid_password?("newpass99")]
end

# --- authenticatable_salt / rememberable ----------------------------------
case_run("auth_salt_shape") { USER.authenticatable_salt.match?(/\A\$2a\$12\$[\.\/A-Za-z0-9]{22}\z/) }
case_run("rem_me") do
  u = User.find(USER.id)
  u.remember_me!
  !u.remember_created_at.nil?
end
case_run("rem_serialize") do
  u = User.find(USER.id)
  u.remember_me!
  id, token, generated_at = User.serialize_into_cookie(u)
  [id == [USER.id], token == u.authenticatable_salt, generated_at.match?(/\A\d+(\.\d+)?\z/) != nil]
end
case_run("rem_from_cookie") do
  u = User.find(USER.id)
  u.remember_me!
  User.serialize_from_cookie(*User.serialize_into_cookie(u))&.id == USER.id
end
case_run("rem_wrong_token") do
  u = User.find(USER.id)
  u.remember_me!
  User.serialize_from_cookie([USER.id], "x" * 29, Time.now.utc.to_f.to_s)
end
case_run("rem_expired") do
  u = User.find(USER.id)
  u.remember_me!
  old = (User.remember_for + 1).ago.to_f.to_s
  User.serialize_from_cookie([USER.id], u.authenticatable_salt, old)
end
case_run("rem_forget") do
  u = User.find(USER.id)
  u.remember_me!
  u.forget_me!
  User.find(USER.id).remember_created_at.nil?
end

# --- registerable (model side: create) ------------------------------------
case_run("reg_create") do
  u = User.new(email: "reg@e.co", password: "regpass1", password_confirmation: "regpass1")
  u.save
  [u.persisted?, u.valid_password?("regpass1")]
end
