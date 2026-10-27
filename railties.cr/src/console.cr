require "./railties_cr"
require "./cli"

# Bake the completion table for the console's line editor, as in
# crails_cli.cr (the user's app types are not in it, stdlib still applies).
Icr.enable_autocomplete!

# Standalone `console` binary (binaries: in shard.yml, installed via carat):
# a shortcut for `crails console` in the app directory — `carat exec console`.
CRails::CLI.run(["console"] + ARGV)
