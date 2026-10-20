Pod::Spec.new do |s|
  s.name             = 'file_image_cropper'
  s.version          = '0.3.6'
  s.summary          = 'System HEIC decoder bridge for file_image_cropper.'
  s.description      = 'Decodes HEIC with Apple ImageIO/Core Image and passes RGBA memory directly to Rust.'
  s.homepage         = 'https://github.com/evgenyuliganets/file_image_cropper'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Evgeny Uliganets' => 'https://github.com/evgenyuliganets' }
  s.source           = { :path => '.' }
  s.source_files     = 'file_image_cropper/Sources/**/*.{h,m,swift}'
  s.public_header_files = 'file_image_cropper/Sources/**/include/**/*.h'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.frameworks = 'CoreImage', 'ImageIO', 'CoreGraphics'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
