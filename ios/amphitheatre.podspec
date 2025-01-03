platform_ios_version = '13.0'

#
# Run `pod lib lint amphitheatre.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'amphitheatre'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter video player and editor.'
  s.description      = <<-DESC
A Flutter video player and editor.

This pod includes the iOS-specific code for the Flutter plugin.
If full Darwin (i.e., macOS) support is added, it will be added here too.
                       DESC
  s.homepage         = 'https://github.com/apollosoftwarexyz/amphitheatre'
  s.license          = { :file => '../LICENSE', :type => 'MIT License' }
  s.author           = { 'Apollo Software Limited' => 'contact@apollosoftware.xyz' }
  s.source           = { :path => '.' }
  s.source_files = 'amphitheatre/Sources/amphitheatre/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, platform_ios_version

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'amphitheatre_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
