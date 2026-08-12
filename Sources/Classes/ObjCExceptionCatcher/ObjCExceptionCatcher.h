#import <Foundation/Foundation.h>

@interface ObjCExceptionCatcher : NSObject

+ (nullable id)catchException:(nullable id _Nullable (^)(void))tryBlock error:(NSError *_Nullable*_Nullable)error;

@end
