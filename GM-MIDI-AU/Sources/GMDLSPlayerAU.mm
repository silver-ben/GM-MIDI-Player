#import <AudioToolbox/AUCocoaUIView.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>

#import "GMDLSShared.h"

namespace {

constexpr UInt8 kGMDefaultProgram = 0;
constexpr UInt8 kProgramMin = 0;
constexpr UInt8 kProgramMax = 127;
constexpr UInt8 kInstrumentControlModeFollowHostMIDI = 0;
constexpr UInt8 kInstrumentControlModeLockPluginUI = 1;
constexpr UInt8 kInstrumentControlModeDefault = kInstrumentControlModeFollowHostMIDI;
constexpr Float64 kDefaultSampleRate = 44100.0;
constexpr UInt32 kPluginVersion = 0x00020001;
constexpr OSStatus kAUNonFatalStatus = 1;
constexpr OSType kPluginSubtype = 'GDFR';
constexpr OSType kPluginManufacturer = 'BSFR';
constexpr size_t kMaxPluginInstances = 32;
constexpr UInt32 kMaxOutputChannels = 2;
constexpr UInt32 kMaxRenderFrames = 32768;

const AUChannelInfo kSupportedOutputConfigs[] = {
    {0, 1},
    {0, 2}
};

const AudioUnitParameterID kSupportedParameterIDs[] = {
    kGMDLSProgramParameterID,
    kGMDLSInstrumentControlModeParameterID
};

class GMDLSPlayerUnit;

struct InstanceSlot {
    std::atomic<void *> self;
    std::atomic<GMDLSPlayerUnit *> unit;
};

static InstanceSlot gInstanceSlots[kMaxPluginInstances];
static std::mutex gInstanceRegistryMutex;

static UInt8 ClampProgram(AudioUnitParameterValue value) {
    long rounded = lroundf(value);
    rounded = std::max<long>(kProgramMin, std::min<long>(kProgramMax, rounded));
    return static_cast<UInt8>(rounded);
}

static UInt8 ClampInstrumentControlMode(AudioUnitParameterValue value) {
    long rounded = lroundf(value);
    rounded = std::max<long>(kInstrumentControlModeFollowHostMIDI, std::min<long>(kInstrumentControlModeLockPluginUI, rounded));
    return static_cast<UInt8>(rounded);
}

static CFArrayRef CopyInstrumentControlModeNames(void) {
    const void *names[] = {
        CFSTR("Follow Host MIDI"),
        CFSTR("Lock Instrument to Plugin UI")
    };
    return CFArrayCreate(kCFAllocatorDefault,
                         names,
                         static_cast<CFIndex>(sizeof(names) / sizeof(names[0])),
                         &kCFTypeArrayCallBacks);
}

static NSString *InstrumentControlModeDisplayName(UInt8 mode) {
    return mode == kInstrumentControlModeLockPluginUI
        ? @"Lock Instrument to Plugin UI"
        : @"Follow Host MIDI";
}

static bool IsFatalStatus(OSStatus status) {
    return !(status == noErr || status == kAUNonFatalStatus);
}

static AudioStreamBasicDescription MakeFloat32PCMFormat(Float64 sampleRate,
                                                        UInt32 channels,
                                                        bool nonInterleaved) {
    AudioStreamBasicDescription format = {};
    format.mSampleRate = sampleRate > 0.0 ? sampleRate : kDefaultSampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat |
                          (nonInterleaved ? kAudioFormatFlagIsNonInterleaved : kAudioFormatFlagIsPacked);
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = 8 * sizeof(Float32);
    format.mBytesPerFrame = static_cast<UInt32>(sizeof(Float32));
    if (!nonInterleaved) {
        format.mBytesPerFrame *= channels;
    }
    format.mBytesPerPacket = format.mBytesPerFrame;
    return format;
}

static bool IsSupportedHostOutputFormat(const AudioStreamBasicDescription &format) {
    if (format.mFormatID != kAudioFormatLinearPCM) {
        return false;
    }

    if ((format.mFormatFlags & kAudioFormatFlagIsFloat) == 0) {
        return false;
    }

    if (format.mSampleRate <= 0.0) {
        return false;
    }

    if (format.mChannelsPerFrame < 1 || format.mChannelsPerFrame > kMaxOutputChannels) {
        return false;
    }

    if (format.mFramesPerPacket != 0 && format.mFramesPerPacket != 1) {
        return false;
    }

    if (format.mBitsPerChannel != 0 && format.mBitsPerChannel != 32) {
        return false;
    }

    const bool nonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    const UInt32 expectedBytesPerFrame = static_cast<UInt32>(sizeof(Float32) * (nonInterleaved ? 1 : format.mChannelsPerFrame));

    if (format.mBytesPerFrame != 0 && format.mBytesPerFrame != expectedBytesPerFrame) {
        return false;
    }

    if (format.mBytesPerPacket != 0 && format.mBytesPerPacket != expectedBytesPerFrame) {
        return false;
    }

    return true;
}

static CFDictionaryRef CopyClassInfo(UInt8 program, UInt8 instrumentControlMode) {
    CFMutableDictionaryRef classInfo = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                 0,
                                                                 &kCFTypeDictionaryKeyCallBacks,
                                                                 &kCFTypeDictionaryValueCallBacks);
    if (classInfo == nullptr) {
        return nullptr;
    }

    SInt32 typeValue = static_cast<SInt32>(kAudioUnitType_MusicDevice);
    SInt32 subtypeValue = static_cast<SInt32>(kPluginSubtype);
    SInt32 manufacturerValue = static_cast<SInt32>(kPluginManufacturer);
    CFNumberRef type = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &typeValue);
    CFNumberRef subtype = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &subtypeValue);
    CFNumberRef manufacturer = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &manufacturerValue);
    if (type == nullptr || subtype == nullptr || manufacturer == nullptr) {
        if (type != nullptr) {
            CFRelease(type);
        }
        if (subtype != nullptr) {
            CFRelease(subtype);
        }
        if (manufacturer != nullptr) {
            CFRelease(manufacturer);
        }
        CFRelease(classInfo);
        return nullptr;
    }

    SInt32 version = static_cast<SInt32>(kPluginVersion);
    CFNumberRef versionNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &version);
    CFMutableDictionaryRef data = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                            0,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    SInt32 programValue = static_cast<SInt32>(program);
    SInt32 instrumentControlModeValue = static_cast<SInt32>(instrumentControlMode);
    CFNumberRef programNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &programValue);
    CFNumberRef instrumentControlModeNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &instrumentControlModeValue);
    if (versionNumber == nullptr || data == nullptr || programNumber == nullptr || instrumentControlModeNumber == nullptr) {
        if (versionNumber != nullptr) {
            CFRelease(versionNumber);
        }
        if (data != nullptr) {
            CFRelease(data);
        }
        if (programNumber != nullptr) {
            CFRelease(programNumber);
        }
        if (instrumentControlModeNumber != nullptr) {
            CFRelease(instrumentControlModeNumber);
        }
        CFRelease(type);
        CFRelease(subtype);
        CFRelease(manufacturer);
        CFRelease(classInfo);
        return nullptr;
    }

    CFDictionarySetValue(classInfo, CFSTR(kAUPresetVersionKey), versionNumber);
    CFDictionarySetValue(classInfo, CFSTR(kAUPresetTypeKey), type);
    CFDictionarySetValue(classInfo, CFSTR(kAUPresetSubtypeKey), subtype);
    CFDictionarySetValue(classInfo, CFSTR(kAUPresetManufacturerKey), manufacturer);
    CFDictionarySetValue(classInfo, CFSTR(kAUPresetNameKey), CFSTR("GM DLS Player"));
    CFDictionarySetValue(data, CFSTR("program"), programNumber);
    CFDictionarySetValue(data, CFSTR("instrumentControlMode"), instrumentControlModeNumber);
    CFDictionarySetValue(classInfo, CFSTR(kAUPresetDataKey), data);

    CFRelease(versionNumber);
    CFRelease(data);
    CFRelease(programNumber);
    CFRelease(instrumentControlModeNumber);
    CFRelease(type);
    CFRelease(subtype);
    CFRelease(manufacturer);
    return classInfo;
}

static bool ExtractUInt8FromClassInfo(CFPropertyListRef classInfo,
                                      CFStringRef key,
                                      UInt8 minValue,
                                      UInt8 maxValue,
                                      UInt8 *outValue) {
    if (classInfo == nullptr || key == nullptr || outValue == nullptr) {
        return false;
    }

    if (CFGetTypeID(classInfo) != CFDictionaryGetTypeID()) {
        return false;
    }

    CFDictionaryRef classInfoDict = static_cast<CFDictionaryRef>(classInfo);
    CFDictionaryRef dataDict = nullptr;
    CFTypeRef dataValue = CFDictionaryGetValue(classInfoDict, CFSTR(kAUPresetDataKey));
    if (dataValue != nullptr && CFGetTypeID(dataValue) == CFDictionaryGetTypeID()) {
        dataDict = static_cast<CFDictionaryRef>(dataValue);
    }

    CFNumberRef number = nullptr;
    if (dataDict != nullptr) {
        CFTypeRef dataKeyValue = CFDictionaryGetValue(dataDict, key);
        if (dataKeyValue != nullptr && CFGetTypeID(dataKeyValue) == CFNumberGetTypeID()) {
            number = static_cast<CFNumberRef>(dataKeyValue);
        }
    }

    if (number == nullptr) {
        CFTypeRef rootKeyValue = CFDictionaryGetValue(classInfoDict, key);
        if (rootKeyValue != nullptr && CFGetTypeID(rootKeyValue) == CFNumberGetTypeID()) {
            number = static_cast<CFNumberRef>(rootKeyValue);
        }
    }

    if (number == nullptr) {
        return false;
    }

    SInt32 rawValue = 0;
    if (!CFNumberGetValue(number, kCFNumberSInt32Type, &rawValue)) {
        return false;
    }

    rawValue = std::max<SInt32>(minValue, std::min<SInt32>(maxValue, rawValue));
    *outValue = static_cast<UInt8>(rawValue);
    return true;
}

static bool ExtractProgramFromClassInfo(CFPropertyListRef classInfo, UInt8 *outProgram) {
    return ExtractUInt8FromClassInfo(classInfo, CFSTR("program"), kProgramMin, kProgramMax, outProgram);
}

static bool ExtractInstrumentControlModeFromClassInfo(CFPropertyListRef classInfo, UInt8 *outMode) {
    return ExtractUInt8FromClassInfo(classInfo,
                                     CFSTR("instrumentControlMode"),
                                     kInstrumentControlModeFollowHostMIDI,
                                     kInstrumentControlModeLockPluginUI,
                                     outMode);
}

static bool IsProgramSelectionLocked(UInt8 mode) {
    return mode == kInstrumentControlModeLockPluginUI;
}

static bool IsBankSelectController(UInt8 controller) {
    return controller == 0 || controller == 32;
}

static bool IsProgramOrBankSelectMIDIEvent(UInt8 statusHigh, UInt8 data1) {
    if (statusHigh == 0xC0) {
        return true;
    }
    if (statusHigh == 0xB0 && IsBankSelectController(data1)) {
        return true;
    }
    return false;
}

class GMDLSPlayerUnit {
public:
    explicit GMDLSPlayerUnit()
        : mSynthUnit(nullptr),
          mCurrentProgram(kGMDefaultProgram),
          mInstrumentControlMode(kInstrumentControlModeDefault),
          mInitialized(false),
          mCreationStatus(noErr),
          mClientOutputFormat(MakeFloat32PCMFormat(kDefaultSampleRate, 2, true)),
          mClientOutputChannels(2),
          mClientFormatInterleaved(false) {
        mCreationStatus = CreateInternalSynth();
        if (mCreationStatus == noErr) {
            mCreationStatus = ConfigureSynthOutputFormat(mClientOutputFormat.mSampleRate, mClientOutputChannels.load(std::memory_order_relaxed));
        }
    }

    ~GMDLSPlayerUnit() {
        if (mSynthUnit != nullptr) {
            if (mInitialized.load(std::memory_order_relaxed)) {
                AudioUnitUninitialize(mSynthUnit);
            }
            AudioComponentInstanceDispose(mSynthUnit);
            mSynthUnit = nullptr;
        }
    }

    OSStatus creationStatus() const {
        return mCreationStatus;
    }

    OSStatus Initialize() {
        if (mCreationStatus != noErr) {
            return mCreationStatus;
        }

        std::lock_guard<std::mutex> lock(mInitMutex);
        if (mInitialized.load(std::memory_order_relaxed)) {
            return noErr;
        }

        OSStatus status = ConfigureSynthOutputFormat(mClientOutputFormat.mSampleRate,
                                                     mClientOutputChannels.load(std::memory_order_relaxed));
        if (IsFatalStatus(status)) {
            return status;
        }

        status = AudioUnitInitialize(mSynthUnit);
        if (IsFatalStatus(status)) {
            return status;
        }

        status = LoadBundledSoundBank();
        if (IsFatalStatus(status)) {
            AudioUnitUninitialize(mSynthUnit);
            return status;
        }

        // Some hosts/synth revisions report a non-fatal status when receiving bank/program events
        // during initialization. Do not fail initialization on that path.
        status = ApplyProgramToAllChannels(mCurrentProgram.load(std::memory_order_relaxed), 0);
        if (IsFatalStatus(status)) {
            AudioUnitUninitialize(mSynthUnit);
            return status;
        }

        mInitialized.store(true, std::memory_order_relaxed);
        return noErr;
    }

    OSStatus Uninitialize() {
        std::lock_guard<std::mutex> lock(mInitMutex);
        if (!mInitialized.load(std::memory_order_relaxed)) {
            return noErr;
        }
        OSStatus status = AudioUnitUninitialize(mSynthUnit);
        mInitialized.store(false, std::memory_order_relaxed);
        return status;
    }

    OSStatus GetPropertyInfo(AudioUnitPropertyID inID,
                             AudioUnitScope inScope,
                             AudioUnitElement inElement,
                             UInt32 *outDataSize,
                             Boolean *outWritable) {
        auto writePropertyInfo = [&](UInt32 dataSize, Boolean writableValue) -> OSStatus {
            if (outDataSize != nullptr) {
                *outDataSize = dataSize;
            }
            if (outWritable != nullptr) {
                *outWritable = writableValue;
            }
            return noErr;
        };

        switch (inID) {
            case kAudioUnitProperty_SupportedNumChannels:
                if (inScope == kAudioUnitScope_Global) {
                    return writePropertyInfo(sizeof(kSupportedOutputConfigs), false);
                }
                return kAudioUnitErr_InvalidScope;

            case kAudioUnitProperty_StreamFormat:
                if (inScope == kAudioUnitScope_Output && inElement == 0) {
                    return writePropertyInfo(sizeof(AudioStreamBasicDescription), true);
                }
                return kAudioUnitErr_InvalidElement;

            case kAudioUnitProperty_ElementCount:
                if (inScope == kAudioUnitScope_Input || inScope == kAudioUnitScope_Output) {
                    return writePropertyInfo(sizeof(UInt32), true);
                }
                return kAudioUnitErr_InvalidScope;

            case kAudioUnitProperty_ParameterList:
                if (inScope == kAudioUnitScope_Global) {
                    return writePropertyInfo(sizeof(kSupportedParameterIDs), false);
                }
                return writePropertyInfo(0, false);

            case kAudioUnitProperty_ParameterInfo:
                if (inScope == kAudioUnitScope_Global &&
                    (inElement == kGMDLSProgramParameterID || inElement == kGMDLSInstrumentControlModeParameterID)) {
                    return writePropertyInfo(sizeof(AudioUnitParameterInfo), false);
                }
                return kAudioUnitErr_InvalidParameter;

            case kAudioUnitProperty_ParameterValueStrings:
                if (inScope == kAudioUnitScope_Global &&
                    (inElement == kGMDLSProgramParameterID || inElement == kGMDLSInstrumentControlModeParameterID)) {
                    return writePropertyInfo(sizeof(CFArrayRef), false);
                }
                return kAudioUnitErr_InvalidParameter;

            case kAudioUnitProperty_ParameterStringFromValue:
                if (inScope == kAudioUnitScope_Global) {
                    return writePropertyInfo(sizeof(AudioUnitParameterStringFromValue), false);
                }
                return kAudioUnitErr_InvalidScope;

            case kAudioUnitProperty_CocoaUI:
                if (inScope == kAudioUnitScope_Global) {
                    return writePropertyInfo(sizeof(AudioUnitCocoaViewInfo), false);
                }
                return kAudioUnitErr_InvalidScope;

            case kAudioUnitProperty_ClassInfo:
            case kAudioUnitProperty_ClassInfoFromDocument:
                if (inScope == kAudioUnitScope_Global) {
                    return writePropertyInfo(sizeof(CFPropertyListRef), true);
                }
                return kAudioUnitErr_InvalidScope;

            default:
                break;
        }

        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        UInt32 synthDataSize = 0;
        Boolean synthWritable = false;
        OSStatus status = AudioUnitGetPropertyInfo(mSynthUnit,
                                                   inID,
                                                   inScope,
                                                   inElement,
                                                   &synthDataSize,
                                                   &synthWritable);
        if (status != noErr) {
            return status;
        }
        return writePropertyInfo(synthDataSize, synthWritable);
    }

    OSStatus GetProperty(AudioUnitPropertyID inID,
                         AudioUnitScope inScope,
                         AudioUnitElement inElement,
                         void *outData,
                         UInt32 *ioDataSize) {
        if (outData == nullptr || ioDataSize == nullptr) {
            return kAudio_ParamError;
        }

        switch (inID) {
            case kAudioUnitProperty_SupportedNumChannels: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidScope;
                }
                if (*ioDataSize < sizeof(kSupportedOutputConfigs)) {
                    return kAudio_ParamError;
                }
                std::memcpy(outData, kSupportedOutputConfigs, sizeof(kSupportedOutputConfigs));
                *ioDataSize = sizeof(kSupportedOutputConfigs);
                return noErr;
            }

            case kAudioUnitProperty_StreamFormat: {
                if (inScope != kAudioUnitScope_Output || inElement != 0) {
                    return (inScope == kAudioUnitScope_Input) ? kAudioUnitErr_InvalidScope : kAudioUnitErr_InvalidElement;
                }
                if (*ioDataSize < sizeof(AudioStreamBasicDescription)) {
                    return kAudio_ParamError;
                }
                auto *format = static_cast<AudioStreamBasicDescription *>(outData);
                *format = mClientOutputFormat;
                *ioDataSize = sizeof(AudioStreamBasicDescription);
                return noErr;
            }

            case kAudioUnitProperty_ElementCount: {
                if (inScope != kAudioUnitScope_Input && inScope != kAudioUnitScope_Output) {
                    return kAudioUnitErr_InvalidScope;
                }
                if (*ioDataSize < sizeof(UInt32)) {
                    return kAudio_ParamError;
                }
                auto *count = static_cast<UInt32 *>(outData);
                *count = (inScope == kAudioUnitScope_Output) ? 1 : 0;
                *ioDataSize = sizeof(UInt32);
                return noErr;
            }

            case kAudioUnitProperty_ParameterList: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidScope;
                }
                if (*ioDataSize < sizeof(kSupportedParameterIDs)) {
                    return kAudio_ParamError;
                }
                std::memcpy(outData, kSupportedParameterIDs, sizeof(kSupportedParameterIDs));
                *ioDataSize = sizeof(kSupportedParameterIDs);
                return noErr;
            }

            case kAudioUnitProperty_ParameterInfo: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidParameter;
                }
                if (*ioDataSize < sizeof(AudioUnitParameterInfo)) {
                    return kAudio_ParamError;
                }

                auto *info = static_cast<AudioUnitParameterInfo *>(outData);
                *info = {};
                if (inElement == kGMDLSProgramParameterID) {
                    strlcpy(info->name, "GM Program", sizeof(info->name));
                    info->minValue = kProgramMin;
                    info->maxValue = kProgramMax;
                    info->defaultValue = kGMDefaultProgram;
                    info->unit = kAudioUnitParameterUnit_Indexed;
                    info->flags = kAudioUnitParameterFlag_IsReadable |
                                  kAudioUnitParameterFlag_IsWritable |
                                  kAudioUnitParameterFlag_HasName |
                                  kAudioUnitParameterFlag_ValuesHaveStrings |
                                  kAudioUnitParameterFlag_HasCFNameString;
                    info->cfNameString = CFStringCreateCopy(kCFAllocatorDefault, CFSTR("GM Program"));
                } else if (inElement == kGMDLSInstrumentControlModeParameterID) {
                    strlcpy(info->name, "Instrument Source", sizeof(info->name));
                    info->minValue = kInstrumentControlModeFollowHostMIDI;
                    info->maxValue = kInstrumentControlModeLockPluginUI;
                    info->defaultValue = kInstrumentControlModeDefault;
                    info->unit = kAudioUnitParameterUnit_Indexed;
                    info->flags = kAudioUnitParameterFlag_IsReadable |
                                  kAudioUnitParameterFlag_IsWritable |
                                  kAudioUnitParameterFlag_HasName |
                                  kAudioUnitParameterFlag_ValuesHaveStrings |
                                  kAudioUnitParameterFlag_HasCFNameString;
                    info->cfNameString = CFStringCreateCopy(kCFAllocatorDefault, CFSTR("Instrument Source"));
                } else {
                    return kAudioUnitErr_InvalidParameter;
                }
                *ioDataSize = sizeof(AudioUnitParameterInfo);
                return noErr;
            }

            case kAudioUnitProperty_ParameterValueStrings: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidParameter;
                }
                if (*ioDataSize < sizeof(CFArrayRef)) {
                    return kAudio_ParamError;
                }
                auto *arrayOut = static_cast<CFArrayRef *>(outData);
                if (inElement == kGMDLSProgramParameterID) {
                    *arrayOut = GMDLSCopyGMProgramNames();
                } else if (inElement == kGMDLSInstrumentControlModeParameterID) {
                    *arrayOut = CopyInstrumentControlModeNames();
                } else {
                    return kAudioUnitErr_InvalidParameter;
                }
                *ioDataSize = sizeof(CFArrayRef);
                return noErr;
            }

            case kAudioUnitProperty_ParameterStringFromValue: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidScope;
                }
                if (*ioDataSize < sizeof(AudioUnitParameterStringFromValue)) {
                    return kAudio_ParamError;
                }

                auto *stringFromValue = static_cast<AudioUnitParameterStringFromValue *>(outData);
                if (stringFromValue->inParamID == kGMDLSProgramParameterID) {
                    AudioUnitParameterValue programValue = stringFromValue->inValue != nullptr
                        ? *stringFromValue->inValue
                        : static_cast<AudioUnitParameterValue>(mCurrentProgram.load(std::memory_order_relaxed));
                    UInt8 program = ClampProgram(programValue);
                    stringFromValue->outString = (__bridge_retained CFStringRef)GMDLSProgramDisplayName(program);
                } else if (stringFromValue->inParamID == kGMDLSInstrumentControlModeParameterID) {
                    AudioUnitParameterValue modeValue = stringFromValue->inValue != nullptr
                        ? *stringFromValue->inValue
                        : static_cast<AudioUnitParameterValue>(mInstrumentControlMode.load(std::memory_order_relaxed));
                    UInt8 mode = ClampInstrumentControlMode(modeValue);
                    stringFromValue->outString = (__bridge_retained CFStringRef)InstrumentControlModeDisplayName(mode);
                } else {
                    stringFromValue->outString = nullptr;
                    return kAudioUnitErr_InvalidParameter;
                }
                *ioDataSize = sizeof(AudioUnitParameterStringFromValue);
                return noErr;
            }

            case kAudioUnitProperty_CocoaUI: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidScope;
                }
                if (*ioDataSize < sizeof(AudioUnitCocoaViewInfo)) {
                    return kAudio_ParamError;
                }

                CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.bensilver.gmdlsplayer"));
                if (bundle == nullptr) {
                    return fnfErr;
                }

                CFURLRef bundleURL = CFBundleCopyBundleURL(bundle);
                if (bundleURL == nullptr) {
                    return fnfErr;
                }

                auto *cocoaInfo = static_cast<AudioUnitCocoaViewInfo *>(outData);
                cocoaInfo->mCocoaAUViewBundleLocation = bundleURL;
                cocoaInfo->mCocoaAUViewClass[0] = CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)kGMDLSCocoaViewFactoryClassName);
                if (cocoaInfo->mCocoaAUViewClass[0] == nullptr) {
                    CFRelease(bundleURL);
                    return memFullErr;
                }
                *ioDataSize = sizeof(AudioUnitCocoaViewInfo);
                return noErr;
            }

            case kAudioUnitProperty_ClassInfo:
            case kAudioUnitProperty_ClassInfoFromDocument: {
                if (inScope != kAudioUnitScope_Global) {
                    return kAudioUnitErr_InvalidScope;
                }
                if (*ioDataSize < sizeof(CFPropertyListRef)) {
                    return kAudio_ParamError;
                }

                CFDictionaryRef classInfo = CopyClassInfo(mCurrentProgram.load(std::memory_order_relaxed),
                                                          mInstrumentControlMode.load(std::memory_order_relaxed));
                if (classInfo == nullptr) {
                    return memFullErr;
                }

                auto *classInfoOut = static_cast<CFPropertyListRef *>(outData);
                *classInfoOut = classInfo;
                *ioDataSize = sizeof(CFPropertyListRef);
                return noErr;
            }

            default:
                break;
        }

        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        return AudioUnitGetProperty(mSynthUnit, inID, inScope, inElement, outData, ioDataSize);
    }

    OSStatus SetProperty(AudioUnitPropertyID inID,
                         AudioUnitScope inScope,
                         AudioUnitElement inElement,
                         const void *inData,
                         UInt32 inDataSize) {
        if (inID == kAudioUnitProperty_CocoaUI) {
            return kAudioUnitErr_PropertyNotWritable;
        }

        if (inID == kAudioUnitProperty_StreamFormat) {
            if (inElement != 0) {
                return kAudioUnitErr_InvalidElement;
            }
            if (inData == nullptr || inDataSize < sizeof(AudioStreamBasicDescription)) {
                return kAudio_ParamError;
            }
            if (mSynthUnit == nullptr) {
                return kAudioUnitErr_Uninitialized;
            }

            const auto requestedFormat = *static_cast<AudioStreamBasicDescription const *>(inData);
            if (inScope == kAudioUnitScope_Input) {
                (void)requestedFormat;
                return noErr;
            }
            if (inScope != kAudioUnitScope_Output) {
                return kAudioUnitErr_InvalidScope;
            }
            if (!IsSupportedHostOutputFormat(requestedFormat)) {
                return kAudioUnitErr_FormatNotSupported;
            }

            const bool hostInterleaved = (requestedFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0;
            const UInt32 channels = requestedFormat.mChannelsPerFrame;
            const Float64 sampleRate = requestedFormat.mSampleRate;

            OSStatus status = ConfigureSynthOutputFormat(sampleRate, channels);
            if (IsFatalStatus(status)) {
                return status;
            }

            mClientOutputFormat = MakeFloat32PCMFormat(sampleRate, channels, !hostInterleaved);
            mClientOutputChannels.store(channels, std::memory_order_relaxed);
            mClientFormatInterleaved.store(hostInterleaved, std::memory_order_relaxed);
            return noErr;
        }

        if (inID == kAudioUnitProperty_ElementCount) {
            if (inScope != kAudioUnitScope_Input && inScope != kAudioUnitScope_Output) {
                return kAudioUnitErr_InvalidScope;
            }
            if (inData == nullptr || inDataSize < sizeof(UInt32)) {
                return kAudio_ParamError;
            }
            UInt32 requestedCount = *static_cast<UInt32 const *>(inData);
            if ((inScope == kAudioUnitScope_Output && requestedCount == 1) ||
                (inScope == kAudioUnitScope_Input && requestedCount == 0)) {
                return noErr;
            }
            return kAudioUnitErr_InvalidPropertyValue;
        }

        if ((inID == kAudioUnitProperty_ClassInfo || inID == kAudioUnitProperty_ClassInfoFromDocument) &&
            inScope == kAudioUnitScope_Global &&
            inElement == 0) {
            if (inData == nullptr || inDataSize < sizeof(CFPropertyListRef)) {
                return kAudio_ParamError;
            }

            auto classInfo = *static_cast<CFPropertyListRef const *>(inData);
            UInt8 program = mCurrentProgram.load(std::memory_order_relaxed);
            if (ExtractProgramFromClassInfo(classInfo, &program)) {
                mCurrentProgram.store(program, std::memory_order_relaxed);
                if (mInitialized.load(std::memory_order_relaxed)) {
                    (void)ApplyProgramToAllChannels(program, 0);
                }
            }

            UInt8 mode = mInstrumentControlMode.load(std::memory_order_relaxed);
            if (ExtractInstrumentControlModeFromClassInfo(classInfo, &mode)) {
                mInstrumentControlMode.store(mode, std::memory_order_relaxed);
            }
            return noErr;
        }

        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        OSStatus status = AudioUnitSetProperty(mSynthUnit, inID, inScope, inElement, inData, inDataSize);
        return IsFatalStatus(status) ? status : noErr;
    }

    OSStatus AddPropertyListener(AudioUnitPropertyID inID,
                                 AudioUnitPropertyListenerProc inProc,
                                 void *inUserData) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitAddPropertyListener(mSynthUnit, inID, inProc, inUserData);
    }

    OSStatus RemovePropertyListener(AudioUnitPropertyID inID,
                                    AudioUnitPropertyListenerProc inProc) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitRemovePropertyListenerWithUserData(mSynthUnit, inID, inProc, nullptr);
    }

    OSStatus RemovePropertyListenerWithUserData(AudioUnitPropertyID inID,
                                                AudioUnitPropertyListenerProc inProc,
                                                void *inUserData) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitRemovePropertyListenerWithUserData(mSynthUnit, inID, inProc, inUserData);
    }

    OSStatus AddRenderNotify(AURenderCallback inProc,
                             void *inUserData) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitAddRenderNotify(mSynthUnit, inProc, inUserData);
    }

    OSStatus RemoveRenderNotify(AURenderCallback inProc,
                                void *inUserData) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitRemoveRenderNotify(mSynthUnit, inProc, inUserData);
    }

    OSStatus ScheduleParameters(const AudioUnitParameterEvent *inEvents,
                                UInt32 inNumEvents) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitScheduleParameters(mSynthUnit, inEvents, inNumEvents);
    }

    OSStatus GetParameter(AudioUnitParameterID inID,
                          AudioUnitScope inScope,
                          AudioUnitElement inElement,
                          AudioUnitParameterValue *outValue) {
        if (outValue == nullptr) {
            return kAudio_ParamError;
        }

        if (inID == kGMDLSProgramParameterID && inScope == kAudioUnitScope_Global) {
            *outValue = static_cast<AudioUnitParameterValue>(mCurrentProgram.load(std::memory_order_relaxed));
            return noErr;
        }
        if (inID == kGMDLSInstrumentControlModeParameterID && inScope == kAudioUnitScope_Global) {
            *outValue = static_cast<AudioUnitParameterValue>(mInstrumentControlMode.load(std::memory_order_relaxed));
            return noErr;
        }

        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        return AudioUnitGetParameter(mSynthUnit, inID, inScope, inElement, outValue);
    }

    OSStatus SetParameter(AudioUnitParameterID inID,
                          AudioUnitScope inScope,
                          AudioUnitElement inElement,
                          AudioUnitParameterValue inValue,
                          UInt32 inBufferOffsetInFrames) {
        if (inID == kGMDLSProgramParameterID && inScope == kAudioUnitScope_Global && inElement == 0) {
            UInt8 program = ClampProgram(inValue);
            mCurrentProgram.store(program, std::memory_order_relaxed);
            if (mInitialized.load(std::memory_order_relaxed)) {
                (void)ApplyProgramToAllChannels(program, inBufferOffsetInFrames);
            }
            return noErr;
        }
        if (inID == kGMDLSInstrumentControlModeParameterID && inScope == kAudioUnitScope_Global && inElement == 0) {
            UInt8 mode = ClampInstrumentControlMode(inValue);
            mInstrumentControlMode.store(mode, std::memory_order_relaxed);
            if (mInitialized.load(std::memory_order_relaxed) && IsProgramSelectionLocked(mode)) {
                (void)ApplyProgramToAllChannels(mCurrentProgram.load(std::memory_order_relaxed), inBufferOffsetInFrames);
            }
            return noErr;
        }

        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        return AudioUnitSetParameter(mSynthUnit, inID, inScope, inElement, inValue, inBufferOffsetInFrames);
    }

    OSStatus Reset(AudioUnitScope inScope, AudioUnitElement inElement) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return AudioUnitReset(mSynthUnit, inScope, inElement);
    }

    OSStatus Render(AudioUnitRenderActionFlags *ioActionFlags,
                    const AudioTimeStamp *inTimeStamp,
                    UInt32 inOutputBusNumber,
                    UInt32 inNumberFrames,
                    AudioBufferList *ioData) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        if (inOutputBusNumber != 0 || ioData == nullptr) {
            return kAudio_ParamError;
        }

        const bool hostInterleaved = mClientFormatInterleaved.load(std::memory_order_relaxed);
        if (!hostInterleaved) {
            return AudioUnitRender(mSynthUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
        }

        const UInt32 channels = mClientOutputChannels.load(std::memory_order_relaxed);
        if (channels < 1 || channels > kMaxOutputChannels) {
            return kAudioUnitErr_FormatNotSupported;
        }

        if (inNumberFrames > kMaxRenderFrames) {
            return kAudioUnitErr_TooManyFramesToProcess;
        }

        if (ioData->mNumberBuffers < 1 || ioData->mBuffers[0].mData == nullptr) {
            return kAudio_ParamError;
        }

        struct ScratchBufferList {
            AudioBufferList list;
            AudioBuffer extraBuffers[kMaxOutputChannels - 1];
        };

        ScratchBufferList scratchList = {};
        AudioBufferList *synthOutput = &scratchList.list;
        synthOutput->mNumberBuffers = channels;
        for (UInt32 channel = 0; channel < channels; ++channel) {
            synthOutput->mBuffers[channel].mNumberChannels = 1;
            synthOutput->mBuffers[channel].mDataByteSize = inNumberFrames * static_cast<UInt32>(sizeof(Float32));
            synthOutput->mBuffers[channel].mData = &mInterleavedScratch[channel * kMaxRenderFrames];
        }

        OSStatus status = AudioUnitRender(mSynthUnit,
                                          ioActionFlags,
                                          inTimeStamp,
                                          inOutputBusNumber,
                                          inNumberFrames,
                                          synthOutput);
        if (IsFatalStatus(status)) {
            return status;
        }

        auto *destination = static_cast<Float32 *>(ioData->mBuffers[0].mData);
        if (channels == 1) {
            std::memcpy(destination,
                        mInterleavedScratch,
                        static_cast<size_t>(inNumberFrames) * sizeof(Float32));
        } else {
            const Float32 *left = &mInterleavedScratch[0];
            const Float32 *right = &mInterleavedScratch[kMaxRenderFrames];
            for (UInt32 frame = 0; frame < inNumberFrames; ++frame) {
                destination[frame * 2] = left[frame];
                destination[frame * 2 + 1] = right[frame];
            }
        }

        ioData->mBuffers[0].mDataByteSize = inNumberFrames * channels * static_cast<UInt32>(sizeof(Float32));
        return noErr;
    }

    OSStatus MIDIEvent(UInt32 inStatus,
                       UInt32 inData1,
                       UInt32 inData2,
                       UInt32 inOffsetSampleFrame) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        const UInt8 statusHigh = static_cast<UInt8>(inStatus & 0xF0);
        const UInt8 channel = static_cast<UInt8>(inStatus & 0x0F);
        const UInt8 data1 = static_cast<UInt8>(inData1 & 0x7F);

        if (IsProgramSelectionLocked(mInstrumentControlMode.load(std::memory_order_relaxed)) &&
            IsProgramOrBankSelectMIDIEvent(statusHigh, data1)) {
            return noErr;
        }

        if (statusHigh == 0xC0 && channel == 0) {
            mCurrentProgram.store(data1, std::memory_order_relaxed);
        }

        return MusicDeviceMIDIEvent(mSynthUnit, inStatus, inData1, inData2, inOffsetSampleFrame);
    }

    OSStatus SysEx(const UInt8 *inData, UInt32 inLength) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }
        return MusicDeviceSysEx(mSynthUnit, inData, inLength);
    }

private:
    OSStatus ConfigureSynthOutputFormat(Float64 sampleRate, UInt32 channels) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        AudioStreamBasicDescription synthFormat = MakeFloat32PCMFormat(sampleRate, channels, true);
        OSStatus status = AudioUnitSetProperty(mSynthUnit,
                                               kAudioUnitProperty_StreamFormat,
                                               kAudioUnitScope_Output,
                                               0,
                                               &synthFormat,
                                               sizeof(synthFormat));
        return IsFatalStatus(status) ? status : noErr;
    }

    OSStatus CreateInternalSynth() {
        AudioComponentDescription description = {};
        description.componentType = kAudioUnitType_MusicDevice;
        description.componentSubType = kAudioUnitSubType_MIDISynth;
        description.componentManufacturer = kAudioUnitManufacturer_Apple;
        description.componentFlags = 0;
        description.componentFlagsMask = 0;

        AudioComponent component = AudioComponentFindNext(nullptr, &description);
        if (component == nullptr) {
            return kAudioUnitErr_FailedInitialization;
        }

        return AudioComponentInstanceNew(component, &mSynthUnit);
    }

    OSStatus LoadBundledSoundBank() {
        CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.bensilver.gmdlsplayer"));
        if (bundle == nullptr) {
            return fnfErr;
        }

        CFURLRef bankURL = CFBundleCopyResourceURL(bundle, CFSTR("gs_instruments"), CFSTR("dls"), nullptr);
        if (bankURL == nullptr) {
            return fnfErr;
        }

        CFURLRef soundBankURL = bankURL;
        OSStatus status = AudioUnitSetProperty(mSynthUnit,
                                               kMusicDeviceProperty_SoundBankURL,
                                               kAudioUnitScope_Global,
                                               0,
                                               &soundBankURL,
                                               sizeof(soundBankURL));
        CFRelease(bankURL);
        return IsFatalStatus(status) ? status : noErr;
    }

    OSStatus ApplyProgramToAllChannels(UInt8 program, UInt32 inOffsetSampleFrame) {
        if (mSynthUnit == nullptr) {
            return kAudioUnitErr_Uninitialized;
        }

        // For gs_instruments.dls with AUMIDISynth, GM melodic patches are at MSB 0 / LSB 0.
        for (UInt8 channel = 0; channel < 16; ++channel) {
            OSStatus status = MusicDeviceMIDIEvent(mSynthUnit, static_cast<UInt32>(0xB0 | channel), 0, 0, inOffsetSampleFrame);
            if (IsFatalStatus(status)) {
                return status;
            }
            status = MusicDeviceMIDIEvent(mSynthUnit, static_cast<UInt32>(0xB0 | channel), 32, kAUSampler_DefaultBankLSB, inOffsetSampleFrame);
            if (IsFatalStatus(status)) {
                return status;
            }
            status = MusicDeviceMIDIEvent(mSynthUnit, static_cast<UInt32>(0xC0 | channel), program, 0, inOffsetSampleFrame);
            if (IsFatalStatus(status)) {
                return status;
            }
        }
        return noErr;
    }

private:
    AudioUnit mSynthUnit;
    std::atomic<UInt8> mCurrentProgram;
    std::atomic<UInt8> mInstrumentControlMode;
    std::atomic<bool> mInitialized;
    OSStatus mCreationStatus;
    AudioStreamBasicDescription mClientOutputFormat;
    std::atomic<UInt32> mClientOutputChannels;
    std::atomic<bool> mClientFormatInterleaved;
    Float32 mInterleavedScratch[kMaxOutputChannels * kMaxRenderFrames];
    std::mutex mInitMutex;
};

static GMDLSPlayerUnit *GetUnit(void *self) {
    if (self == nullptr) {
        return nullptr;
    }

    for (auto &slot : gInstanceSlots) {
        void *slotSelf = slot.self.load(std::memory_order_acquire);
        if (slotSelf == self) {
            return slot.unit.load(std::memory_order_acquire);
        }
    }
    return nullptr;
}

static bool RegisterUnit(void *self, GMDLSPlayerUnit *unit) {
    if (self == nullptr || unit == nullptr) {
        return false;
    }

    std::lock_guard<std::mutex> lock(gInstanceRegistryMutex);
    for (auto &slot : gInstanceSlots) {
        if (slot.self.load(std::memory_order_relaxed) == nullptr) {
            slot.unit.store(unit, std::memory_order_relaxed);
            slot.self.store(self, std::memory_order_release);
            return true;
        }
    }
    return false;
}

static GMDLSPlayerUnit *UnregisterUnit(void *self) {
    if (self == nullptr) {
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(gInstanceRegistryMutex);
    for (auto &slot : gInstanceSlots) {
        if (slot.self.load(std::memory_order_relaxed) == self) {
            GMDLSPlayerUnit *unit = slot.unit.load(std::memory_order_relaxed);
            slot.self.store(nullptr, std::memory_order_release);
            slot.unit.store(nullptr, std::memory_order_relaxed);
            return unit;
        }
    }

    return nullptr;
}

static OSStatus FactoryOpen(void *self, AudioComponentInstance inInstance) {
    if (inInstance == nullptr) {
        return kAudio_ParamError;
    }

    auto *unit = new (std::nothrow) GMDLSPlayerUnit();
    if (unit == nullptr) {
        return memFullErr;
    }

    OSStatus status = unit->creationStatus();
    if (status != noErr) {
        delete unit;
        return status;
    }

    if (!RegisterUnit(self, unit)) {
        delete unit;
        return memFullErr;
    }

    return noErr;
}

static OSStatus FactoryClose(void *self) {
    auto *unit = UnregisterUnit(self);
    delete unit;
    return noErr;
}

static OSStatus DispatchComponentVersion(void *) {
    return static_cast<OSStatus>(kPluginVersion);
}

static OSStatus DispatchComponentCanDo(void *, SInt16 selector) {
    switch (selector) {
        case kAudioUnitInitializeSelect:
        case kAudioUnitUninitializeSelect:
        case kAudioUnitGetPropertyInfoSelect:
        case kAudioUnitGetPropertySelect:
        case kAudioUnitSetPropertySelect:
        case kAudioUnitAddPropertyListenerSelect:
        case kAudioUnitRemovePropertyListenerSelect:
        case kAudioUnitRemovePropertyListenerWithUserDataSelect:
        case kAudioUnitAddRenderNotifySelect:
        case kAudioUnitRemoveRenderNotifySelect:
        case kAudioUnitScheduleParametersSelect:
        case kAudioUnitGetParameterSelect:
        case kAudioUnitSetParameterSelect:
        case kAudioUnitRenderSelect:
        case kAudioUnitResetSelect:
        case kMusicDeviceMIDIEventSelect:
        case kMusicDeviceSysExSelect:
        case kComponentVersionSelect:
        case kComponentCanDoSelect:
            return 1;
        default:
            return 0;
    }
}

static OSStatus DispatchInitialize(void *self) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->Initialize() : kAudio_ParamError;
}

static OSStatus DispatchUninitialize(void *self) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->Uninitialize() : kAudio_ParamError;
}

static OSStatus DispatchGetPropertyInfo(void *self,
                                        AudioUnitPropertyID inID,
                                        AudioUnitScope inScope,
                                        AudioUnitElement inElement,
                                        UInt32 *outDataSize,
                                        Boolean *outWritable) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->GetPropertyInfo(inID, inScope, inElement, outDataSize, outWritable) : kAudio_ParamError;
}

static OSStatus DispatchGetProperty(void *self,
                                    AudioUnitPropertyID inID,
                                    AudioUnitScope inScope,
                                    AudioUnitElement inElement,
                                    void *outData,
                                    UInt32 *ioDataSize) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->GetProperty(inID, inScope, inElement, outData, ioDataSize) : kAudio_ParamError;
}

static OSStatus DispatchSetProperty(void *self,
                                    AudioUnitPropertyID inID,
                                    AudioUnitScope inScope,
                                    AudioUnitElement inElement,
                                    const void *inData,
                                    UInt32 inDataSize) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->SetProperty(inID, inScope, inElement, inData, inDataSize) : kAudio_ParamError;
}

static OSStatus DispatchAddPropertyListener(void *self,
                                            AudioUnitPropertyID inID,
                                            AudioUnitPropertyListenerProc inProc,
                                            void *inUserData) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->AddPropertyListener(inID, inProc, inUserData) : kAudio_ParamError;
}

static OSStatus DispatchRemovePropertyListener(void *self,
                                               AudioUnitPropertyID inID,
                                               AudioUnitPropertyListenerProc inProc) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->RemovePropertyListener(inID, inProc) : kAudio_ParamError;
}

static OSStatus DispatchRemovePropertyListenerWithUserData(void *self,
                                                           AudioUnitPropertyID inID,
                                                           AudioUnitPropertyListenerProc inProc,
                                                           void *inUserData) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->RemovePropertyListenerWithUserData(inID, inProc, inUserData) : kAudio_ParamError;
}

static OSStatus DispatchAddRenderNotify(void *self,
                                        AURenderCallback inProc,
                                        void *inUserData) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->AddRenderNotify(inProc, inUserData) : kAudio_ParamError;
}

static OSStatus DispatchRemoveRenderNotify(void *self,
                                           AURenderCallback inProc,
                                           void *inUserData) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->RemoveRenderNotify(inProc, inUserData) : kAudio_ParamError;
}

static OSStatus DispatchScheduleParameters(void *self,
                                           const AudioUnitParameterEvent *inEvents,
                                           UInt32 inNumEvents) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->ScheduleParameters(inEvents, inNumEvents) : kAudio_ParamError;
}

static OSStatus DispatchGetParameter(void *self,
                                     AudioUnitParameterID inID,
                                     AudioUnitScope inScope,
                                     AudioUnitElement inElement,
                                     AudioUnitParameterValue *outValue) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->GetParameter(inID, inScope, inElement, outValue) : kAudio_ParamError;
}

static OSStatus DispatchSetParameter(void *self,
                                     AudioUnitParameterID inID,
                                     AudioUnitScope inScope,
                                     AudioUnitElement inElement,
                                     AudioUnitParameterValue inValue,
                                     UInt32 inBufferOffsetInFrames) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->SetParameter(inID, inScope, inElement, inValue, inBufferOffsetInFrames) : kAudio_ParamError;
}

static OSStatus DispatchRender(void *self,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inOutputBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->Render(ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData) : kAudio_ParamError;
}

static OSStatus DispatchReset(void *self,
                              AudioUnitScope inScope,
                              AudioUnitElement inElement) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->Reset(inScope, inElement) : kAudio_ParamError;
}

static OSStatus DispatchMIDIEvent(void *self,
                                  UInt32 inStatus,
                                  UInt32 inData1,
                                  UInt32 inData2,
                                  UInt32 inOffsetSampleFrame) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->MIDIEvent(inStatus, inData1, inData2, inOffsetSampleFrame) : kAudio_ParamError;
}

static OSStatus DispatchSysEx(void *self,
                              const UInt8 *inData,
                              UInt32 inLength) {
    auto *unit = GetUnit(self);
    return unit != nullptr ? unit->SysEx(inData, inLength) : kAudio_ParamError;
}

static AudioComponentMethod FactoryLookup(SInt16 selector) {
    switch (selector) {
        case kAudioUnitInitializeSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchInitialize);
        case kAudioUnitUninitializeSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchUninitialize);
        case kAudioUnitGetPropertyInfoSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchGetPropertyInfo);
        case kAudioUnitGetPropertySelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchGetProperty);
        case kAudioUnitSetPropertySelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchSetProperty);
        case kAudioUnitAddPropertyListenerSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchAddPropertyListener);
        case kAudioUnitRemovePropertyListenerSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchRemovePropertyListener);
        case kAudioUnitRemovePropertyListenerWithUserDataSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchRemovePropertyListenerWithUserData);
        case kAudioUnitAddRenderNotifySelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchAddRenderNotify);
        case kAudioUnitRemoveRenderNotifySelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchRemoveRenderNotify);
        case kAudioUnitScheduleParametersSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchScheduleParameters);
        case kAudioUnitGetParameterSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchGetParameter);
        case kAudioUnitSetParameterSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchSetParameter);
        case kAudioUnitRenderSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchRender);
        case kAudioUnitResetSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchReset);
        case kMusicDeviceMIDIEventSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchMIDIEvent);
        case kMusicDeviceSysExSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchSysEx);
        case kComponentVersionSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchComponentVersion);
        case kComponentCanDoSelect:
            return reinterpret_cast<AudioComponentMethod>(DispatchComponentCanDo);
        default:
            return nullptr;
    }
}

} // namespace

extern "C" void *GMDLSPlayerFactory(const AudioComponentDescription *) {
    static AudioComponentPlugInInterface pluginInterface = {
        FactoryOpen,
        FactoryClose,
        FactoryLookup,
        nullptr
    };

    return &pluginInterface;
}
