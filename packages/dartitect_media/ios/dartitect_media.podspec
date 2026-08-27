Pod::Spec.new do |s|
  s.name             = 'dartitect_media'
  s.version          = '1.0.0-rc.3'
  s.summary          = 'Explicit Android and iOS gallery image boundary.'
  s.description      = 'Typed gallery access and image save without automatic permission requests.'
  s.homepage         = 'https://github.com/ftr-tuta/dartitect'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ftr' => 'ftr@tuta.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.swift_version = '5.0'
  s.frameworks = 'Photos'
end
