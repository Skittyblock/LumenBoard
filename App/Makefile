include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LumenBoard
$(APPLICATION_NAME)_FILES = $(wildcard *.m *.swift) ../Shared/LMThemeLibrary.m ../Shared/LMShared.swift
$(APPLICATION_NAME)_FRAMEWORKS = UIKit QuartzCore ImageIO
$(APPLICATION_NAME)_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new
$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.plist
$(APPLICATION_NAME)_SWIFT_BRIDGING_HEADER = LumenBoard-Bridging-Header.h

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
$(APPLICATION_NAME)_SWIFTFLAGS += -D THEOS_PACKAGE_SCHEME_ROOTHIDE
endif

include $(THEOS_MAKE_PATH)/application.mk
