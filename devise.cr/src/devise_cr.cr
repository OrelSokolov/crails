# devise_cr — port of Devise (P0): database_authenticatable +
# validatable + rememberable + registerable (bcrypt with pepper,
# byte-compatible with the gem), session handler (Warden replacement)
# and the Iteration 6 JWT access/refresh pair with rotation.

require "active_record_cr"
require "./encryptor"
require "./models"
require "./sessions"
require "./jwt"
