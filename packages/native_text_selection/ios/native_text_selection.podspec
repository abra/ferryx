Pod::Spec.new do |s|
  s.name             = 'native_text_selection'
  s.version          = '0.1.0'
  s.summary          = 'System text selection for Flutter-rendered text geometry.'
  s.description      = s.summary
  s.homepage         = 'https://github.com/abra/readflex'
  s.license          = { :type => 'MIT' }
  s.author           = 'Readflex contributors'
  s.source           = { :path => '.' }
  s.source_files     = 'native_text_selection/Sources/native_text_selection/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.test_spec 'Tests' do |tests|
    tests.source_files = 'native_text_selection/Tests/**/*.swift'
    tests.requires_app_host = true
  end
end
