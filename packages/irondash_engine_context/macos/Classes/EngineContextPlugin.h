#import <FlutterMacOS/FlutterMacOS.h>

@interface IrondashEngineContextPlugin : NSObject <FlutterPlugin>
+ (nullable NSView *)getFlutterView:(int64_t)engineHandle;
+ (nullable id<FlutterTextureRegistry>)getTextureRegistry:(int64_t)engineHandle;
+ (nullable id<FlutterBinaryMessenger>)getBinaryMessenger:(int64_t)engineHandle;
@end
