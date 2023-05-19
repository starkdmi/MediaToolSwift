#import <Foundation/Foundation.h>

@interface ObjCExceptionCatcher : NSObject

+ (nullable id)catchException:(nullable id _Nullable (^)())tryBlock error:(NSError *_Nullable*_Nullable)error;

@end
