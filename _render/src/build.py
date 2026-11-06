import subprocess,os
R='/Users/vunguyen/Desktop/iphone-18-pro-max-high-quality-3d-model/'
env=dict(os.environ); env['DEVELOPER_DIR']='/Users/vunguyen/Desktop/Xcode-beta.app/Contents/Developer'
subprocess.Popen(['xcodebuild','-project',R+'ChargeFuzeApp/ChargeFuze.xcodeproj','-scheme','ChargeFuze','-configuration','Debug','-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator','-derivedDataPath','/tmp/cfz_dd','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO','build'],stdout=open(R+'_vert/build.txt','w'),stderr=subprocess.STDOUT,env=env)
