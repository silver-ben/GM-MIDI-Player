#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

extern const AudioUnitParameterID kGMDLSProgramParameterID;
extern const AudioUnitParameterID kGMDLSInstrumentControlModeParameterID;
extern NSString * const kGMDLSCocoaViewFactoryClassName;

#ifdef __cplusplus
extern "C" {
#endif

CFArrayRef GMDLSCopyGMProgramNames(void);
NSString *GMDLSProgramDisplayName(UInt8 programNumber);

#ifdef __cplusplus
}
#endif
