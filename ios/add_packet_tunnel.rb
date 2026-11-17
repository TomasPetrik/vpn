#!/usr/bin/env ruby
# Adds PacketTunnel Network Extension target to Runner.xcodeproj and embeds it.
require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

if project.targets.any? { |t| t.name == 'PacketTunnel' }
  puts 'PacketTunnel target already exists'
  exit 0
end

# Group + files
pt_group = project.main_group.find_subpath('PacketTunnel', true)
pt_group.set_source_tree('<group>')
pt_group.set_path('PacketTunnel')

provider_ref = pt_group.new_file('PacketTunnelProvider.swift')
info_ref = pt_group.new_file('Info.plist')
entitlements_ref = pt_group.new_file('PacketTunnel.entitlements')

target = project.new_target(
  :app_extension,
  'PacketTunnel',
  :ios,
  '15.0',
  nil,
  :swift
)

target.add_file_references([provider_ref])

# Ensure product type is network extension appex (app_extension is correct)
product = target.product_reference
product.name = 'PacketTunnel.appex'
product.path = 'PacketTunnel.appex'

%w[Debug Release Profile].each do |config_name|
  config = target.build_configurations.find { |c| c.name == config_name }
  next unless config
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'cz.tomaspetrik.petrikvpn.PacketTunnel'
  config.build_settings['INFOPLIST_FILE'] = 'PacketTunnel/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'PacketTunnel/PacketTunnel.entitlements'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = '56S59F5D36'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
  # PacketTunnel has no Flutter Generated.xcconfig — do not use FLUTTER_BUILD_*.
  config.build_settings['CURRENT_PROJECT_VERSION'] = '2'
  config.build_settings['MARKETING_VERSION'] = '1.0.1'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['PRODUCT_NAME'] = 'PacketTunnel'
  config.build_settings['REGISTER_APP_GROUPS'] = 'YES'
end

# Embed Foundation Extensions into Runner (must be BEFORE "Thin Binary"
# or Xcode reports a dependency cycle with Flutter's script phase).
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13' # PlugIns
end
build_file = embed.add_file_reference(product)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

phases = runner.build_phases
thin = phases.find { |ph| ph.display_name == 'Thin Binary' }
if thin && phases.include?(embed)
  phases.delete(embed)
  phases.insert(phases.index(thin), embed)
end

runner.add_dependency(target)

project.save
puts 'Added PacketTunnel target and embedded into Runner'
