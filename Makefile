TWEAK_NAME = XMSForCouria
XMSForCouria_FILES = Tweak.mm
XMSForCouria_FRAMEWORKS = UIKit
XMSForCouria_PRIVATE_FRAMEWORKS = BackBoardServices
XMSForCouria_LIBRARIES = substrate

export TARGET=iphone:clang
export ARCHS = armv7 armv7s arm64
export TARGET_IPHONEOS_DEPLOYMENT_VERSION = 3.0
export TARGET_IPHONEOS_DEPLOYMENT_VERSION_armv7s = 6.0
export TARGET_IPHONEOS_DEPLOYMENT_VERSION_arm64 = 7.0
export ADDITIONAL_OBJCFLAGS = -fobjc-arc

include theos/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
