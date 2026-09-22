# One-off: add the NearbyWalkWidget extension target to loci.xcodeproj.
#
# Xcode's "add target" UI is the usual way; this script does the same edits
# with the xcodeproj gem so the change is reviewable and repeatable. The app
# target uses synchronized folders, so the shared attributes file is added to
# the extension by reference, not copied.
#
# Run from the loci/ directory: bundle exec ruby scripts/add_widget_extension.rb
require "xcodeproj"

PROJECT = "loci.xcodeproj"
EXT_NAME = "NearbyWalkWidget"
EXT_DIR = EXT_NAME
TEAM = "84X9WYBF36"
SHARED_FILE = "loci/Shared/NearbyWalkAttributes.swift"

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == "loci" } or abort("app target not found")
abort("#{EXT_NAME} already exists") if project.targets.any? { |t| t.name == EXT_NAME }

ext = project.new_target(:app_extension, EXT_NAME, :ios, "26.2")
ext.product_type = "com.apple.product-type.app-extension"

group = project.main_group.new_group(EXT_NAME, EXT_DIR)
sources = %w[NearbyWalkWidgetBundle.swift NearbyWalkLiveActivity.swift].map { |f| group.new_file(f) }
sources << project.main_group.new_file(SHARED_FILE)
sources.each { |ref| ext.add_file_references([ref]) }
info_plist = group.new_file("Info.plist")

ext.build_configurations.each do |config|
  bundle_suffix = config.name == "Beta" ? "com.fernandocorreia.loci.beta" : "com.fernandocorreia.loci"
  config.build_settings.merge!(
    "PRODUCT_BUNDLE_IDENTIFIER" => "#{bundle_suffix}.#{EXT_NAME}",
    "PRODUCT_NAME" => EXT_NAME,
    "INFOPLIST_FILE" => "#{EXT_DIR}/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Nearby walk",
    "INFOPLIST_KEY_NSHumanReadableCopyright" => "",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_DEFAULT_ACTOR_ISOLATION" => "MainActor",
    "SWIFT_APPROACHABLE_CONCURRENCY" => "YES",
    "IPHONEOS_DEPLOYMENT_TARGET" => "26.2",
    "TARGETED_DEVICE_FAMILY" => "1,2",
    "DEVELOPMENT_TEAM" => TEAM,
    "CODE_SIGN_STYLE" => "Automatic",
    "SKIP_INSTALL" => "YES",
    "GENERATE_INFOPLIST_FILE" => "NO",
    # Same version as the app; agvtool (fastlane increment_build_number) bumps every target.
    "MARKETING_VERSION" => app.build_configurations.find { |c| c.name == config.name }.build_settings["MARKETING_VERSION"] || "1.0",
    "CURRENT_PROJECT_VERSION" => app.build_configurations.find { |c| c.name == config.name }.build_settings["CURRENT_PROJECT_VERSION"] || "1",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "AccentColor",
    "SWIFT_EMIT_LOC_STRINGS" => "YES",
    "LD_RUNPATH_SEARCH_PATHS" => ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
  )
end
ext.frameworks_build_phase.clear

# The app depends on the extension and embeds it.
app.add_dependency(ext)
embed = app.build_phases.find { |p| p.respond_to?(:name) && p.name == "Embed Foundation Extensions" }
embed ||= app.new_copy_files_build_phase("Embed Foundation Extensions")
embed.dst_subfolder_spec = "13"
embed.dst_path = ""
build_file = embed.add_file_reference(ext.product_reference)
build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

project.save
puts "added #{EXT_NAME}: #{sources.size} sources, embedded in loci"
