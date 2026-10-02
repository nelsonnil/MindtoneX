#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCObjC : NSObject

/// Ejecuta el bloque y devuelve la descripción de la NSException si la hubo (Swift no puede capturarlas).
+ (nullable NSString *)performSafely:(void (NS_NOESCAPE ^)(void))block
    NS_SWIFT_NAME(performSafely(_:));

@end

NS_ASSUME_NONNULL_END
