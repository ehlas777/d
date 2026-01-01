//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<ffmpeg_kit_flutter_full_gpl/FFmpegKitFlutterPlugin.h>)
#import <ffmpeg_kit_flutter_full_gpl/FFmpegKitFlutterPlugin.h>
#else
@import ffmpeg_kit_flutter_full_gpl;
#endif

#if __has_include(<path_provider_foundation/PathProviderPlugin.h>)
#import <path_provider_foundation/PathProviderPlugin.h>
#else
@import path_provider_foundation;
#endif

#if __has_include(<record_darwin/RecordPlugin.h>)
#import <record_darwin/RecordPlugin.h>
#else
@import record_darwin;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FFmpegKitFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"FFmpegKitFlutterPlugin"]];
  [PathProviderPlugin registerWithRegistrar:[registry registrarForPlugin:@"PathProviderPlugin"]];
  [RecordPlugin registerWithRegistrar:[registry registrarForPlugin:@"RecordPlugin"]];
}

@end
