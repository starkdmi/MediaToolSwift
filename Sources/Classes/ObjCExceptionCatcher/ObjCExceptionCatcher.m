#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (nullable id)catchException:(nullable id(^)())tryBlock error:(NSError **)error {
    @try {
        return tryBlock ? tryBlock() : nil;
    }
    @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:exception.name code:0 userInfo:@{
                NSUnderlyingErrorKey: exception,
                NSLocalizedDescriptionKey: exception.reason,
                @"CallStackSymbols": exception.callStackSymbols
            }];
        }
        return nil;
    }
}

@end