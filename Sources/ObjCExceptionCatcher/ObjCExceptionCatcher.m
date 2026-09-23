#import "ObjCExceptionCatcher.h"

BOOL CPTryObjC(void (NS_NOESCAPE ^block)(void), NSError * _Nullable * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%@: %@",
                                 exception.name, exception.reason ?: @""];
            *error = [NSError errorWithDomain:@"ru.olya.camprompt.objc"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }
}
