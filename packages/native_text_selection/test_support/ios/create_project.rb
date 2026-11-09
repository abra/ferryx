require 'fileutils'
require 'xcodeproj'

root = File.expand_path('../..', __dir__)
fixtures = __dir__
dir = File.expand_path(ARGV.fetch(0, File.join(root, '.dart_tool/native-selection-ios')))
FileUtils.mkdir_p(dir)
project = Xcodeproj::Project.new(File.join(dir, 'NativeSelectionHarness.xcodeproj'))
app = project.new_target(:application, 'NativeSelectionHarness', :ios, '15.0')
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.abra.NativeSelectionHarness'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
app.add_file_references([
  File.join(fixtures, 'Harness.swift'),
  File.join(root, 'ios/native_text_selection/Sources/native_text_selection/SelectionGeometry.swift'),
  File.join(root, 'ios/native_text_selection/Sources/native_text_selection/NativeSelectionControls.swift'),
  File.join(root, 'ios/native_text_selection/Sources/native_text_selection/NativeSelectionView.swift')
].map { |path| project.main_group.new_file(path) })
backend = project.new_target(:framework, 'native_text_selection', :ios, '15.0')
backend.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.abra.NativeSelectionBackend'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['MACH_O_TYPE'] = 'staticlib'
  config.build_settings['ENABLE_TESTABILITY'] = 'YES'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
backend.add_file_references([
  File.join(root, 'ios/native_text_selection/Sources/native_text_selection/SelectionGeometry.swift'),
  File.join(root, 'ios/native_text_selection/Sources/native_text_selection/NativeSelectionControls.swift'),
  File.join(root, 'ios/native_text_selection/Sources/native_text_selection/NativeSelectionView.swift')
].map { |path| project.main_group.new_file(path) })
unit = project.new_target(:unit_test_bundle, 'SelectionBackendTests', :ios, '15.0')
unit.add_dependency(app)
unit.add_dependency(backend)
unit.frameworks_build_phase.add_file_reference(backend.product_reference)
unit.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.abra.NativeSelectionBackendTests'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/NativeSelectionHarness.app/NativeSelectionHarness'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
unit.add_file_references([project.main_group.new_file(File.join(root, 'ios/native_text_selection/Tests/native_text_selectionTests/SelectionGeometryTests.swift'))])
tests = project.new_target(:ui_test_bundle, 'HarnessUITests', :ios, '15.0')
tests.add_dependency(app)
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.abra.NativeSelectionHarnessUITests'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TEST_TARGET_NAME'] = 'NativeSelectionHarness'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
tests.add_file_references([project.main_group.new_file(File.join(fixtures, 'HarnessUITests.swift'))])
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_build_target(unit)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(unit)
scheme.save_as(project.path, 'NativeSelectionHarness', true)
project.save
