const { withPodfile, withFinalizedMod, IOSConfig } = require('@expo/config-plugins');
const xcode = require('xcode');

// Enables Mac Catalyst so `xcodebuild -destination 'platform=macOS,variant=Mac Catalyst'`
// produces a real, double-clickable Mac app instead of the CLI-unlaunchable
// "Designed for iPad" build. Both edits below are made on the GENERATED
// ios/ project, so without this plugin they're wiped by every
// `expo prebuild --clean`.
module.exports = function withMacCatalyst(config) {
  // 1. The RN community template's Podfile hardcodes mac_catalyst_enabled
  // false in its post_install call. Flip it — this is a straight string
  // patch because prebuild-config exposes no config knob for it.
  config = withPodfile(config, (config) => {
    const before = config.modResults.contents;
    const after = before.replace(
      ':mac_catalyst_enabled => false',
      ':mac_catalyst_enabled => true'
    );
    if (after === before) {
      throw new Error(
        'withMacCatalyst: did not find ":mac_catalyst_enabled => false" in the generated Podfile — the RN template changed, update this plugin.'
      );
    }
    config.modResults.contents = after;
    return config;
  });

  // 2. SUPPORTS_MACCATALYST + TARGETED_DEVICE_FAMILY, on the main app
  // target AND every other iphoneos-SDK target (CalMindWidget) — NOT the
  // watchos-SDK ones (CalMindWatch, CalMindComplication), which cannot run
  // under Catalyst at all and which Xcode already skips on its own.
  //
  // The widget target needs this too, proven the hard way: it's pulled
  // into the Catalyst build graph as a dependency of the main app (the
  // "Embed App Extensions" phase creates that edge regardless of Catalyst
  // support), and without its OWN SUPPORTS_MACCATALYST it still gets
  // scheduled to compile — just with the wrong search paths, which surfaced
  // as "no such module ExpoModulesCore" in its shared
  // @bacons/apple-targets source file, not as a "target skipped" no-op.
  //
  // This has to be withFinalizedMod, not withXcodeProject OR
  // withDangerousMod: @bacons/apple-targets adds CalMindWidget/Watch/
  // Complication through its OWN separate mod pipeline (a custom
  // "xcodeProjectBeta2" base mod), and empirically its write runs AFTER
  // BOTH withXcodeProject's and withDangerousMod's — proven by testing
  // each: the main target kept these settings, the widget target never
  // existed yet when either of those ran (only "MyCalMind" was in the
  // file). withFinalizedMod is the one guarantee Expo gives for "after
  // every other mod for this platform, custom ones included."
  config = withFinalizedMod(config, [
    'ios',
    (config) => {
      const pbxprojPath = IOSConfig.Paths.getPBXProjectPath(config.modRequest.projectRoot);
      const project = xcode.project(pbxprojPath);
      project.parseSync();

      const nativeTargets = project.pbxNativeTargetSection();
      const configurationLists = project.pbxXCConfigurationList();
      const buildConfigSection = project.pbxXCBuildConfigurationSection();

      for (const key of Object.keys(nativeTargets)) {
        const target = nativeTargets[key];
        if (!target.name || !target.buildConfigurationList) continue;

        const configurationList = configurationLists[target.buildConfigurationList];
        if (!configurationList) continue;

        const sdkroots = configurationList.buildConfigurations
          .map(({ value }) => buildConfigSection[value])
          .filter(Boolean)
          .map((c) => c.buildSettings && c.buildSettings.SDKROOT);
        if (sdkroots.some((sdk) => sdk === 'watchos')) continue;

        for (const { value: buildConfigId } of configurationList.buildConfigurations) {
          const buildConfig = buildConfigSection[buildConfigId];
          if (!buildConfig || !buildConfig.buildSettings) continue;
          buildConfig.buildSettings.SUPPORTS_MACCATALYST = 'YES';
          buildConfig.buildSettings.DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = 'NO';
          // "1,2" (iPhone, iPad) plus "6" (Mac Catalyst).
          buildConfig.buildSettings.TARGETED_DEVICE_FAMILY = '"1,2,6"';
        }
      }

      // 3. Exclude the watch companion from the Catalyst destination. A Mac
      // doesn't pair with an Apple Watch, and Xcode agrees at build time —
      // "This target is built for macOS but contains embedded content
      // (CalMindWatch.app) built for watchOS, which is not allowed" — its
      // own suggested fix is exactly this: a Platforms filter on the embed.
      // iOS installs still need this build file un-filtered, hence "ios"
      // rather than removing it outright.
      const copyPhases = project.hash.project.objects['PBXCopyFilesBuildPhase'] || {};
      for (const key of Object.keys(copyPhases)) {
        const phase = copyPhases[key];
        if (!phase || phase.name !== '"Embed Watch Content"') continue;
        for (const { value: buildFileId } of phase.files || []) {
          const buildFile = project.hash.project.objects['PBXBuildFile'][buildFileId];
          if (buildFile) buildFile.platformFilter = 'ios';
        }
      }

      require('fs').writeFileSync(pbxprojPath, project.writeSync());
      return config;
    },
  ]);

  return config;
};
