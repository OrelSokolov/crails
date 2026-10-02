require "railties_cr"

require "../config/application"
require "../app/controllers/**"
require "../config/routes"
require "../config/environments/development"
require "../config/environments/production"

CRails.application.initialize!
CRails.application.boot(ARGV)