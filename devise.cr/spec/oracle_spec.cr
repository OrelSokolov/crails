# Oracle spec: the Crystal port must reproduce oracle/expected.yml
# exactly (captured from devise 4.9.4 over SQLite in-memory). Same case
# IDs, no edits; values use the same \n/\t escape protocol.

require "spec"
require "crypto/bcrypt"
require "../src/devise_cr"

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

def escape(s : String | Bool) : String
  s = s.to_s
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

TEST_URL = ENV["DEVISE_TEST_URL"]? ||
           "postgres://root@/crails_as_test?host=/var/run/postgresql"

ActiveRecord::Base.establish_connection(TEST_URL)
ActiveRecord::Base.connection.exec("DELETE FROM users")

class User < ActiveRecord::Base
  devise :database_authenticatable, :rememberable, :validatable
end

class PepperedUser < ActiveRecord::Base
  set_table_name "users"
  devise :database_authenticatable, :validatable
  self.pepper = "s3cr3t-pepper"
end

USER = User.create!({"email" => "a@b.c", "password" => "secret123",
                     "password_confirmation" => "secret123"})

CASES = {
  "pw_digest_shape" => -> { USER.encrypted_password.to_s.matches?(/^\$2a\$12\$[.\/A-Za-z0-9]{53}$/).to_s },
  "pw_valid"        => -> { User.find?(USER.id.not_nil!).not_nil!.valid_password?("secret123").to_s },
  "pw_wrong"        => -> { User.find?(USER.id.not_nil!).not_nil!.valid_password?("nope").to_s },
  "pw_blank_hash"   => -> { User.new({"email" => "x@y.z"}).valid_password?("any").to_s },
  "pw_deterministic_by_salt" => -> {
    ep = USER.encrypted_password.to_s
    salt22 = ep[7, 22]
    Crypto::Bcrypt.new("secret123", salt22, 12).to_s.starts_with?(ep[0, 29]).to_s
  },
  "pw_pepper_digest" => -> {
    u = PepperedUser.new
    u.password = "secret123"
    ep = u.encrypted_password.to_s
    Crypto::Bcrypt.new("secret123s3cr3t-pepper", ep[7, 22], 12).to_s == ep
  },
  "pw_pepper_valid" => -> {
    u = PepperedUser.create!({"email" => "p@q.r", "password" => "secret123",
                              "password_confirmation" => "secret123"})
    [u.valid_password?("secret123"), u.valid_password?("secret123s3cr3t-pepper")].inspect
  },
  # --- validatable ---
  "val_ok" => -> {
    u = User.new({"email" => "ok@e.co"})
    u.password = "longenough"
    u.password_confirmation = "longenough"
    u.valid?.to_s
  },
  "val_email_missing" => -> {
    u = User.new
    u.password = "longenough"
    u.password_confirmation = "longenough"
    [u.valid?, u.errors.group_by_attribute.has_key?("email")].inspect
  },
  "val_email_bad" => -> {
    u = User.new({"email" => "no-at"})
    u.password = "longenough"
    u.password_confirmation = "longenough"
    [u.valid?, u.errors.group_by_attribute.has_key?("email")].inspect
  },
  "val_email_uniq" => -> {
    u = User.new({"email" => USER.email.not_nil!.upcase})
    u.password = "longenough"
    u.password_confirmation = "longenough"
    [u.valid?, u.errors.group_by_attribute.has_key?("email")].inspect
  },
  "val_pw_short" => -> {
    u = User.new({"email" => "s@e.co"})
    u.password = "abc"
    u.password_confirmation = "abc"
    [u.valid?, u.errors.group_by_attribute.has_key?("password")].inspect
  },
  "val_pw_long" => -> {
    u = User.new({"email" => "s@e.co"})
    u.password = "x" * 129
    u.password_confirmation = "x" * 129
    [u.valid?, u.errors.group_by_attribute.has_key?("password")].inspect
  },
  "val_pw_mismatch" => -> {
    u = User.new({"email" => "s@e.co"})
    u.password = "longenough"
    u.password_confirmation = "different"
    [u.valid?, u.errors.group_by_attribute.has_key?("password_confirmation")].inspect
  },
  "val_update_no_pw" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.email = "new@e.co"
    u.valid?.to_s
  },
  # --- update_with_password ---
  "uwp_ok" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    res = u.update_with_password({"current_password" => "secret123", "email" => "uwp@e.co"})
    [res, User.find?(USER.id.not_nil!).not_nil!.email].inspect
  },
  "uwp_bad_pw" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    res = u.update_with_password({"current_password" => "WRONG", "email" => "hacked@e.co"})
    [res, u.errors.group_by_attribute.has_key?("current_password"),
     User.find?(USER.id.not_nil!).not_nil!.email].inspect
  },
  "uwp_new_password" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    res = u.update_with_password({"current_password" => "secret123",
                                  "password" => "newpass99", "password_confirmation" => "newpass99"})
    [res, User.find?(USER.id.not_nil!).not_nil!.valid_password?("newpass99")].inspect
  },
  # --- authenticatable_salt / rememberable ---
  "auth_salt_shape" => -> { USER.authenticatable_salt.not_nil!.matches?(/^\$2a\$12\$[.\/A-Za-z0-9]{22}$/).to_s },
  "rem_me" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.remember_me!
    (!u.remember_created_at.nil?).to_s
  },
  "rem_serialize" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.remember_me!
    key, token, generated_at = User.serialize_into_cookie(u)
    [key == [USER.id.not_nil!], token == u.authenticatable_salt,
     generated_at.matches?(/^\d+(\.\d+)?$/) != nil].inspect
  },
  "rem_from_cookie" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.remember_me!
    User.serialize_from_cookie(*User.serialize_into_cookie(u)).try { |u| u.id == USER.id }.to_s
  },
  "rem_wrong_token" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.remember_me!
    User.serialize_from_cookie([USER.id.not_nil!], "x" * 29, ("%f" % Time.utc.to_unix_f)).inspect
  },
  "rem_expired" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.remember_me!
    old = ("%f" % (Time.utc - (Devise.remember_for + 1.second)).to_unix_f)
    User.serialize_from_cookie([USER.id.not_nil!], u.authenticatable_salt.not_nil!, old).inspect
  },
  "rem_forget" => -> {
    u = User.find?(USER.id.not_nil!).not_nil!
    u.remember_me!
    u.forget_me!
    User.find?(USER.id.not_nil!).not_nil!.remember_created_at.nil?.to_s
  },
  # --- registerable ---
  "reg_create" => -> {
    u = User.new({"email" => "reg@e.co"})
    u.password = "regpass1"
    u.password_confirmation = "regpass1"
    u.save
    [u.persisted?, u.valid_password?("regpass1")].inspect
  },
}

describe "devise oracle" do
  CASES.each do |id, block|
    it id do
      expected = EXPECTED[id]? || fail("missing expected value for #{id}")
      escape(block.call).should eq expected
    end
  end
end
