# Rodin Essential product packages.
PRODUCT_PACKAGES += \
    RodinEssential \
    rodin_daemon

# Development-only health client. Production user builds expose the daemon
# only through the certificate-bound application domain.
PRODUCT_PACKAGES_DEBUG += \
    rodin_ctl
