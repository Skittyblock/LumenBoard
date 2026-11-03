include $(THEOS)/makefiles/common.mk

# Injected into iconservicesagent and every app: Foundation only, no UIKit.
TWEAK_NAME = LumenBoardCore
LumenBoardCore_FILES = $(wildcard *.m *.x)
LumenBoardCore_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations
LumenBoardCore_FRAMEWORKS = Foundation CoreGraphics CoreText ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk
