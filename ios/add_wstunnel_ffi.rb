#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'PacketTunnel' }
abort('PacketTunnel target not found') unless target

xcframework_rel = 'ThirdParty/WstunnelFFI/WstunnelFFI.xcframework'
xcframework_abs = File.join(__dir__, xcframework_rel)
abort("Missing #{xcframework_abs}") unless File.directory?(xcframework_abs)

# File reference (relative to project)
existing = project.files.find { |f| f.path&.end_with?('WstunnelFFI.xcframework') }
file_ref = existing || project.new_file(xcframework_rel)

# Embed/link in Frameworks phase
frameworks = target.frameworks_build_phase
unless frameworks.files.any? { |bf| bf.file_ref == file_ref || bf.file_ref&.path&.end_with?('WstunnelFFI.xcframework') }
  frameworks.add_file_reference(file_ref)
  puts 'Linked WstunnelFFI.xcframework into PacketTunnel Frameworks'
else
  puts 'WstunnelFFI.xcframework already linked'
end

# Build settings for module map / headers / linking
%w[Debug Release Profile].each do |cfg_name|
  config = target.build_configurations.find { |c| c.name == cfg_name }
  next unless config

  settings = config.build_settings
  settings['OTHER_LDFLAGS'] = Array(settings['OTHER_LDFLAGS']).flatten
  settings['OTHER_LDFLAGS'] = ['$(inherited)'] if settings['OTHER_LDFLAGS'].empty?
  unless settings['OTHER_LDFLAGS'].any? { |f| f.to_s.include?('wstunnel_ffi') }
    settings['OTHER_LDFLAGS'] << '-lwstunnel_ffi'
  end
  # Resolve symbols from static XCFramework
  unless settings['OTHER_LDFLAGS'].any? { |f| f.to_s.include?('-force_load') && f.to_s.include?('wstunnel') }
    # Prefer FRAMEWORK_SEARCH_PATHS based link via xcframework; -force_load path is fragile.
  end

  settings['LIBRARY_SEARCH_PATHS'] = Array(settings['LIBRARY_SEARCH_PATHS']).flatten
  settings['LIBRARY_SEARCH_PATHS'] << '$(inherited)' unless settings['LIBRARY_SEARCH_PATHS'].include?('$(inherited)')
  # Device + Simulator slices (Xcode picks the matching arch when both are listed).
  %w[
    $(PROJECT_DIR)/ThirdParty/WstunnelFFI/WstunnelFFI.xcframework/ios-arm64
    $(PROJECT_DIR)/ThirdParty/WstunnelFFI/WstunnelFFI.xcframework/ios-arm64_x86_64-simulator
  ].each do |lib_path|
    settings['LIBRARY_SEARCH_PATHS'] << lib_path unless settings['LIBRARY_SEARCH_PATHS'].include?(lib_path)
  end

  # Shared headers (identical across slices; stable path outside the xcframework).
  settings['HEADER_SEARCH_PATHS'] = Array(settings['HEADER_SEARCH_PATHS']).flatten
  settings['HEADER_SEARCH_PATHS'] << '$(inherited)' unless settings['HEADER_SEARCH_PATHS'].include?('$(inherited)')
  hdr = '$(PROJECT_DIR)/ThirdParty/WstunnelFFI/include'
  settings['HEADER_SEARCH_PATHS'] << hdr unless settings['HEADER_SEARCH_PATHS'].include?(hdr)

  settings['SWIFT_INCLUDE_PATHS'] = Array(settings['SWIFT_INCLUDE_PATHS']).flatten
  settings['SWIFT_INCLUDE_PATHS'] << hdr unless settings['SWIFT_INCLUDE_PATHS'].include?(hdr)

  settings['OTHER_SWIFT_FLAGS'] = Array(settings['OTHER_SWIFT_FLAGS']).flatten
  flag = '-Xcc -fmodule-map-file=$(PROJECT_DIR)/ThirdParty/WstunnelFFI/include/module.modulemap'
  settings['OTHER_SWIFT_FLAGS'] = settings['OTHER_SWIFT_FLAGS'].reject { |f| f.to_s.include?('WstunnelFFI') || f.to_s.include?('wstunnel_ffi') }
  settings['OTHER_SWIFT_FLAGS'] << flag

  # Needed for Rust staticlib (atomics / unwind)
  %w[-lc++ -framework Security -framework SystemConfiguration].each do |flag|
    settings['OTHER_LDFLAGS'] << flag unless settings['OTHER_LDFLAGS'].any? { |f| f.to_s == flag }
  end
end

project.save
puts 'Saved Runner.xcodeproj'
