const { withAndroidManifest, AndroidConfig } = require('@expo/config-plugins');

/** Adds Android permissions required by sentinel-android native module. */
function withSentinelAndroid(config) {
  return withAndroidManifest(config, (cfg) => {
    const permissions = [
      'android.permission.READ_PHONE_STATE',
      'android.permission.QUERY_ALL_PACKAGES',
    ];
    for (const permission of permissions) {
      AndroidConfig.Manifest.addUsesPermissionString(cfg.modResults, permission);
    }
    return cfg;
  });
}

module.exports = withSentinelAndroid;
