#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and turns a raised NSException into an NSError.
///
/// Swift cannot catch Objective-C exceptions, and AVFoundation raises one
/// (instead of returning an error) when AVCaptureMovieFileOutput is given
/// output settings the Mac does not support. Without this shim a rejected
/// bitrate setting would crash the app at the moment recording starts.
BOOL CPTryObjC(void (NS_NOESCAPE ^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
