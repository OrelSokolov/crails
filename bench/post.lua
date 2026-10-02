-- POST /posts for the 101-ar-crud benchmark. Sent as JSON: Rails'
-- out-of-the-box CSRF protection only verifies form requests, and
-- CRails has no CSRF layer yet — this keeps both sides comparable
-- without touching application code. Both controllers generate the
-- title server-side, the body only needs to parse.
local i = 0
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
request = function()
  i = i + 1
  wrk.body = string.format('{"title":"bench-%d","views":0}', i)
  return wrk.request(0, "/posts")
end
