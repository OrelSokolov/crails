require "spec"
require "../src/action_view_cr"

class HelperHost
  include ActionView::Helpers
end

describe "ActionView::Helpers (Iteration 0 slice)" do
  it "h escapes HTML" do
    host = HelperHost.new
    host.h("<b>a & b</b>").should eq("&lt;b&gt;a &amp; b&lt;/b&gt;")
    host.h(42).should eq("42")
  end

  it "html_escape escapes a string" do
    HelperHost.new.html_escape(%q{"x" <br>}).should eq(%q{&quot;x&quot; &lt;br&gt;})
  end
end
