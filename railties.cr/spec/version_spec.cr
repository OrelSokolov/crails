# CRails::VERSION выводится из shard.yml при компиляции (макро в
# src/railties_cr.cr) — спек фиксирует, что константа действительно
# совпадает с версией манифеста, который лёг рядом с исходниками.

require "spec"
require "../src/railties_cr"

describe "CRails::VERSION" do
  it "matches the shard.yml the sources were compiled from" do
    manifest = File.read(File.join(__DIR__, "..", "shard.yml"))
    line = manifest.lines.find { |l| l.starts_with?("version:") }
    line.should_not be_nil
    CRails::VERSION.should eq(line.not_nil!.split(":")[1].strip)
  end
end
