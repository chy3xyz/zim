require 'xcodeproj'

# 获取参数
new_bundle_identifier = ARGV[0]
root_path = ARGV[1]
app_name = ARGV[2]
extensions = ARGV[3..-1]

# 路径到 iOS 工程
project_path = root_path + '/ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Updating Bundle Identifier to '#{new_bundle_identifier}'"

# 更新 Runner target 的 PRODUCT_BUNDLE_IDENTIFIER
runner_target = project.targets.find { |t| t.name == 'Runner' }
if runner_target
  runner_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = app_name
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = new_bundle_identifier
    puts "Updated Runner's PRODUCT_BUNDLE_IDENTIFIER to '#{config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']}, PRODUCT_NAME to '#{config.build_settings['PRODUCT_NAME']}'"
  end
else
  puts "Warning: Runner target not found."
end

# 更新扩展的 PRODUCT_BUNDLE_IDENTIFIER
extensions.each do |extension|
  ext_target = project.targets.find { |t| t.name == extension }
  if ext_target
    ext_target.build_configurations.each do |config|
      config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{new_bundle_identifier}.#{extension}"
      puts "Updated #{extension}'s PRODUCT_BUNDLE_IDENTIFIER to '#{config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']}'"
    end
  else
    puts "Warning: #{extension} target not found."
  end
end

project.save
puts "Bundle Identifier updated successfully."

