#!/usr/bin/env ruby
# frozen_string_literal: true

require "openssl"
require "base64"
require "json"
require "optparse"
require "open3"

options = {
  env: "production",
  topic: "com.fernandocorreia.loci.beta",
  title: "Loci Test",
  body: "Push notifications are working!",
  badge: 1,
  sound: "default"
}

OptionParser.new do |opts|
  opts.banner = "Usage: scripts/send_push.rb [options]"

  opts.on("-t", "--token TOKEN", "APNS device token (hex string, required)") do |v|
    options[:token] = v.gsub(/[\s<>]/, "")
  end
  opts.on("-m", "--body MESSAGE", "Notification message body") do |v|
    options[:body] = v
  end
  opts.on("--title TITLE", "Notification title") do |v|
    options[:title] = v
  end
  opts.on("-e", "--env ENV", "APNS environment: 'production' (default, for TestFlight & AppStore) or 'sandbox' (for Xcode debug)") do |v|
    options[:env] = v.downcase
  end
  opts.on("--topic BUNDLE_ID", "Bundle identifier (default: com.fernandocorreia.loci.beta)") do |v|
    options[:topic] = v
  end
  opts.on("--prod", "Shortcut for App Store release bundle ID (com.fernandocorreia.loci)") do
    options[:topic] = "com.fernandocorreia.loci"
    options[:env] = "production"
  end
  opts.on("-b", "--badge NUM", Integer, "App icon badge count") do |v|
    options[:badge] = v
  end
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit 0
  end
end.parse!

# Load .env if present
env_file = File.expand_path("../loci/fastlane/.env", __dir__)
if File.exist?(env_file)
  File.foreach(env_file) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    k, v = line.split("=", 2)
    ENV[k] ||= v if k && v
  end
end

key_id = ENV["APNS_KEY_ID"] || "QG4A86C28M"
team_id = ENV["APNS_TEAM_ID"] || "84X9WYBF36"
key_path = ENV["APNS_KEY_PATH"] ? File.expand_path(ENV["APNS_KEY_PATH"], File.expand_path("../loci", __dir__)) : File.expand_path("../loci/fastlane/AuthKey_QG4A86C28M.p8", __dir__)

unless options[:token]
  warn "Error: Missing required --token argument."
  warn "Usage: ./scripts/send_push.rb --token <device-token> [--title <title>] [--body <message>]"
  exit 1
end

unless File.exist?(key_path)
  warn "Error: Key file not found at #{key_path}"
  exit 1
end

def base64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

header = { alg: "ES256", kid: key_id }
payload = { iss: team_id, iat: Time.now.to_i }

header_b64 = base64url(header.to_json)
payload_b64 = base64url(payload.to_json)
signing_input = "#{header_b64}.#{payload_b64}"

ec_key = OpenSSL::PKey::EC.new(File.read(key_path))
der_signature = ec_key.sign(OpenSSL::Digest::SHA256.new, signing_input)

asn1 = OpenSSL::ASN1.decode(der_signature)
r = asn1.value[0].value.to_s(2).rjust(32, "\x00")
s = asn1.value[1].value.to_s(2).rjust(32, "\x00")
jwt = "#{signing_input}.#{base64url(r + s)}"

host = options[:env] == "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
url = "https://#{host}/3/device/#{options[:token]}"

apns_payload = {
  aps: {
    alert: {
      title: options[:title],
      body: options[:body]
    },
    sound: options[:sound],
    badge: options[:badge]
  }
}.to_json

token_display = options[:token].length > 16 ? "#{options[:token][0..9]}...#{options[:token][-6..-1]}" : options[:token]

puts "==> Sending APNS push notification"
puts "    Host:        #{host} (#{options[:env]})"
puts "    Topic:       #{options[:topic]}"
puts "    Token:       #{token_display}"
puts "    Payload:     #{apns_payload}"

cmd = [
  "curl", "-s", "-i", "--http2",
  "-H", "authorization: bearer #{jwt}",
  "-H", "apns-topic: #{options[:topic]}",
  "-H", "apns-push-type: alert",
  "-H", "apns-priority: 10",
  "-d", apns_payload,
  url
]

output, _status = Open3.capture2(*cmd)

headers, _, body = output.partition("\r\n\r\n")
first_line = headers.lines.first&.strip

if first_line =~ /200/
  apns_id = headers[/apns-id:\s*([^\r\n]+)/i, 1]
  puts "\n✅ SUCCESS: Push notification delivered!"
  puts "   apns-id: #{apns_id}"
else
  warn "\n❌ FAILED: #{first_line}"
  warn "   Response: #{body}" unless body.empty?
  exit 1
end
