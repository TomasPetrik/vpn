#!/usr/bin/env ruby
# Adds local WireGuardKit package + WireGuardGoBridgeiOS target.
# Requires ios/ThirdParty/wireguard-apple (see bootstrap in README / clone script).
# Idempotent. Run from ios/: ruby add_wireguard_kit.rb
require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

LOCAL_PACKAGE = 'ThirdParty/wireguard-apple'
BRIDGE_NAME = 'WireGuardGoBridgeiOS'
GO_DIR = 'ThirdParty/wireguard-apple/Sources/WireGuardKitGo'

abort("Missing #{LOCAL_PACKAGE} — clone wireguard-apple first") unless Dir.exist?(File.join(__dir__, LOCAL_PACKAGE))

packet_tunnel = project.targets.find { |t| t.name == 'PacketTunnel' }
abort('PacketTunnel target not found') unless packet_tunnel

# Remove broken remote package refs to git.zx2c4.com
project.root_object.package_references.dup.each do |ref|
  url = ref.respond_to?(:repositoryURL) ? ref.repositoryURL.to_s : ''
  path = ref.respond_to?(:relative_path) ? ref.relative_path.to_s : ''
  next unless url.include?('wireguard-apple') || path.include?('wireguard-apple')
  if url.include?('git.zx2c4.com') || url.include?('github.com/WireGuard')
    project.root_object.package_references.delete(ref)
    puts "Removed remote package ref #{url}"
  end
end

# Local package reference
package_ref = project.root_object.package_references.find do |ref|
  ref.isa == 'XCLocalSwiftPackageReference' && ref.relative_path.to_s.include?('wireguard-apple')
end
unless package_ref
  package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package_ref.relative_path = LOCAL_PACKAGE
  project.root_object.package_references << package_ref
  puts "Added local SPM package #{LOCAL_PACKAGE}"
end

# WireGuardKit product dependency on PacketTunnel
pkg_dep = packet_tunnel.package_product_dependencies.find { |d| d.product_name == 'WireGuardKit' }
unless pkg_dep
  pkg_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  pkg_dep.product_name = 'WireGuardKit'
  packet_tunnel.package_product_dependencies << pkg_dep

  frameworks = packet_tunnel.frameworks_build_phase
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = pkg_dep
  frameworks.files << build_file
  puts 'Linked WireGuardKit to PacketTunnel'
end
# Always point product dep at local package
pkg_dep.package = package_ref

# External Build System target for wireguard-go
bridge = project.targets.find { |t| t.name == BRIDGE_NAME }
unless bridge
  bridge = project.new(Xcodeproj::Project::Object::PBXLegacyTarget)
  bridge.name = BRIDGE_NAME
  bridge.product_name = BRIDGE_NAME
  bridge.build_tool_path = '/usr/bin/make'
  bridge.build_arguments_string = '$(ACTION)'
  bridge.pass_build_settings_in_environment = '1'

  configs = project.new(Xcodeproj::Project::Object::XCConfigurationList)
  %w[Debug Release Profile].each do |cfg_name|
    cfg = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    cfg.name = cfg_name
    cfg.build_settings = { 'SDKROOT' => 'iphoneos' }
    configs.build_configurations << cfg
  end
  configs.default_configuration_name = 'Release'
  bridge.build_configuration_list = configs
  project.root_object.targets << bridge
  puts "Added legacy target #{BRIDGE_NAME}"
end
bridge.build_working_directory = GO_DIR

unless packet_tunnel.dependencies.any? { |d| d.target && d.target.name == BRIDGE_NAME }
  proxy = project.new(Xcodeproj::Project::Object::PBXContainerItemProxy)
  proxy.container_portal = project.root_object.uuid
  proxy.proxy_type = '1'
  proxy.remote_global_id_string = bridge.uuid
  proxy.remote_info = BRIDGE_NAME

  dep = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  dep.name = BRIDGE_NAME
  dep.target = bridge
  dep.target_proxy = proxy
  packet_tunnel.dependencies << dep
  puts "PacketTunnel → depends on #{BRIDGE_NAME}"
end

project.save
puts 'Saved Runner.xcodeproj'
