#import <Foundation/Foundation.h>

@interface ObjCExceptionCatcher : NSObject

+ (nullable id)catchException:(nullable id(^)())tryBlock error:(NSError **)error;

@end