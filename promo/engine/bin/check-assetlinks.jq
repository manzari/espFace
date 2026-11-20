# Prints one line per problem in a Digital Asset Links statement list; no
# output means valid. Run with -rs so an empty file is caught too.
def fingerprint: type == "string" and test("^([0-9A-F]{2}:){31}[0-9A-F]{2}$");

if length != 1 then "must contain exactly one JSON value"
elif (.[0] | type) != "array" then "top level must be a JSON array"
elif (.[0] | length) == 0 then "statement list is empty"
else .[0] | to_entries[] | "statement \(.key): " + (.value |
  if type != "object" then "must be an object"
  elif has("include") then empty
  elif (.relation | type != "array" or length == 0 or any(.[]; type != "string"))
    then "relation must be a non-empty array of strings"
  elif (.target | type) != "object" then "target must be an object"
  elif .target.namespace != "android_app" then empty
  elif (.target.package_name | type != "string" or . == "")
    then "target.package_name must be a non-empty string"
  elif (.target.sha256_cert_fingerprints | type != "array" or length == 0)
    then "target.sha256_cert_fingerprints must be a non-empty array"
  else .target.sha256_cert_fingerprints[] | select(fingerprint | not)
    | "bad fingerprint \(tojson) (want 32 uppercase hex bytes, colon-separated)"
  end)
end
