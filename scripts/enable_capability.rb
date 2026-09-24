#!/usr/bin/env ruby
# frozen_string_literal: true

# Enable a capability on both Loci App IDs through the App Store Connect API.
#
#   ruby scripts/enable_capability.rb ASSOCIATED_DOMAINS
#   ruby scripts/enable_capability.rb APPLE_ID_AUTH
#
# `fastlane produce enable_services` cannot do this: it only takes an Apple ID
# login, not the API key. A capability that is missing from the App ID is
# what makes a Release fail with "Provisioning profile doesn't include the
# X capability"; after this, dispatch seed-signing so match regenerates the
# profiles, then rerun the release. Reads ASC_KEY_ID / ASC_ISSUER_ID /
# ASC_KEY_P8 (base64) from loci/fastlane/.env, or the file LOCI_FASTLANE_ENV names.

require "base64"
require "spaceship"

ENV_FILE = ENV.fetch("LOCI_FASTLANE_ENV", File.expand_path("../loci/fastlane/.env", __dir__))
BUNDLE_IDS = %w[com.fernandocorreia.loci com.fernandocorreia.loci.beta].freeze

def load_env(path)
  File.readlines(path).each do |line|
    next if line.strip.empty? || line.start_with?("#")
    key, value = line.strip.split("=", 2)
    ENV[key] ||= value.to_s.delete_prefix('"').delete_suffix('"')
  end
end

capability = ARGV.fetch(0) { abort "usage: enable_capability.rb <CAPABILITY_TYPE>" }
type = Spaceship::ConnectAPI::BundleIdCapability::Type.const_get(capability)
settings = capability == "APPLE_ID_AUTH" ? [{ key: "APPLE_ID_AUTH_APP_CONSENT", options: [{ key: "PRIMARY_APP_CONSENT" }] }] : []

load_env(ENV_FILE)
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"),
  issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  key: Base64.decode64(ENV.fetch("ASC_KEY_P8"))
)

BUNDLE_IDS.each do |identifier|
  bundle = Spaceship::ConnectAPI::BundleId.find(identifier, includes: "bundleIdCapabilities")
  abort "#{identifier}: not found" unless bundle
  existing = (bundle.bundle_id_capabilities || []).map(&:capability_type)
  if existing.include?(type)
    puts "#{identifier}: #{capability} already on"
    next
  end
  begin
    bundle.create_capability(type, settings: settings)
    puts "#{identifier}: #{capability} enabled"
  rescue Spaceship::UnexpectedResponse => e
    raise unless e.message.include?("already")
    puts "#{identifier}: #{capability} already on"
  end
end
