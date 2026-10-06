include $(TOPDIR)/rules.mk

  PKG_NAME:=xunlei-kuainiao-service
  PKG_VERSION:=1.0.0
  PKG_RELEASE:=1

  PKG_LICENSE:=MIT
  PKG_MAINTAINER:=OpenWrt Community

  include $(INCLUDE_DIR)/package.mk

  define Package/xunlei-kuainiao-service
    SECTION:=net
    CATEGORY:=Network
    TITLE:=Xunlei KuaiNiao Speed Boost Service
    DEPENDS:=+bash +curl +jq
    PKGARCH:=all
  endef

  define Package/xunlei-kuainiao-service/description
    迅雷快鸟宽带提速服务
  endef

  define Build/Compile
  endef

  define Package/xunlei-kuainiao-service/install
        $(INSTALL_DIR) $(1)/usr/share/xunlei-kuainiao
        $(INSTALL_BIN) $(PKG_BUILD_DIR)/src/xunlei-kuainiao.sh $(1)/usr/share/xunlei-kuainiao/xunlei-kuainiao.sh
        $(INSTALL_DIR) $(1)/usr/bin
        $(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/bin/xunlei-kuainiao-cli $(1)/usr/bin/xunlei-kuainiao-cli
        $(INSTALL_DIR) $(1)/etc/config
        $(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/config/xunlei-kuainiao $(1)/etc/config/xunlei-kuainiao
        $(INSTALL_DIR) $(1)/etc/init.d
        $(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/xunlei-kuainiao $(1)/etc/init.d/xunlei-kuainiao
  endef

  $(eval $(call BuildPackage,xunlei-kuainiao-service))
