//
//  TouchBarPrivateApi-Bridging.h
//  MTMR
//
//  Private Apple APIs used from Swift.
//

#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import "TouchBarPrivateApi.h"
#import "TouchBarSupport.h"

NS_ASSUME_NONNULL_BEGIN

// DisplayServices.framework: brightness of Apple displays (the built-in panel), level 0…1.
extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);

// IOKit: I2C access to external displays through the Apple Silicon display coprocessor (DDC/CI).
typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef _Nullable IOAVServiceCreateWithService(CFAllocatorRef _Nullable allocator, io_service_t service) CF_RETURNS_RETAINED;
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

NS_ASSUME_NONNULL_END
