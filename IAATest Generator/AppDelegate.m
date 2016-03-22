//
//  AppDelegate.m
//  IAATest
//
//  Created by Michael Tyson on 19/09/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import "AppDelegate.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&result);
        return NO;
    }
    return YES;
}

#define USE_HARDWARE_SAMPLE_RATE


@interface AppDelegate () {
    AudioUnit _audioUnit;
    AudioStreamBasicDescription _audioDescription;
}
@property (nonatomic, strong) id observerToken;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self setupAudioSystem];
    [self startAudioSystem];
    return YES;
}

-(void)dealloc {
    [self teardownAudioSystem];
}

-(void)applicationDidBecomeActive:(UIApplication *)application {
    [self updateAudioUnitStatus];
}

-(void)applicationDidEnterBackground:(UIApplication *)application {
    [self updateAudioUnitStatus];
}

- (void)setupAudioSystem {
    
    NSError *error = nil;
    if ( ![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error] ) {
        NSLog(@"Couldn't set audio session category: %@", error);
    }
    
    if ( ![[AVAudioSession sharedInstance] setPreferredIOBufferDuration:(128.0/44100.0) error:&error] ) {
        NSLog(@"Couldn't set preferred buffer duration: %@", error);
    }
    
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Couldn't set audio session active: %@", error);
    }
    
    // Create the audio unit
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_RemoteIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    checkResult(AudioComponentInstanceNew(inputComponent, &_audioUnit), "AudioComponentInstanceNew");

    // Set the stream formats
    memset(&_audioDescription, 0, sizeof(_audioDescription));
    _audioDescription.mFormatID          = kAudioFormatLinearPCM;
    _audioDescription.mFormatFlags       = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    _audioDescription.mChannelsPerFrame  = 2;
    _audioDescription.mBytesPerPacket    = sizeof(float);
    _audioDescription.mFramesPerPacket   = 1;
    _audioDescription.mBytesPerFrame     = sizeof(float);
    _audioDescription.mBitsPerChannel    = 8 * sizeof(float);
#ifdef USE_HARDWARE_SAMPLE_RATE
    _audioDescription.mSampleRate        = [AVAudioSession sharedInstance].sampleRate;
#else
    _audioDescription.mSampleRate        = 44100.0;
#endif
    
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &_audioDescription, sizeof(_audioDescription)),
                "kAudioUnitProperty_StreamFormat");
    
    // Set the render callback
    AURenderCallbackStruct rcbs = { .inputProc = audioUnitRenderCallback, .inputProcRefCon = (__bridge void *)(self) };
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &rcbs, sizeof(rcbs)),
                "kAudioUnitProperty_SetRenderCallback");
    
    UInt32 framesPerSlice = 4096;
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &framesPerSlice, sizeof(framesPerSlice)),
                "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice");
    
    // Initialize the audio unit
    checkResult(AudioUnitInitialize(_audioUnit), "AudioUnitInitialize");
    
    // Watch for session interruptions
    self.observerToken =
    [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        NSInteger type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
        if ( type == AVAudioSessionInterruptionTypeBegan ) {
            [self stopAudioSystem];
        } else {
            if ( ![self startAudioSystem] ) {
                // Work around an iOS 7 audio interruption bug
                [self teardownAudioSystem];
                [self setupAudioSystem];
                [self startAudioSystem];
            }
        }
    }];
    
    // Watch for IAA connections
    checkResult(AudioUnitAddPropertyListener(_audioUnit, kAudioUnitProperty_IsInterAppConnected, audioUnitPropertyChange, (__bridge void*)self), "AudioUnitAddPropertyListener");
    
#ifdef USE_HARDWARE_SAMPLE_RATE
    // Watch for stream format changes
    checkResult(AudioUnitAddPropertyListener(_audioUnit, kAudioUnitProperty_StreamFormat, audioUnitStreamFormatChanged, (__bridge void*)self), "AudioUnitAddPropertyListener");
#endif
    
    // Publish audio unit
    AudioComponentDescription remoteDesc = {
        .componentType = kAudioUnitType_RemoteGenerator,
        .componentManufacturer = 'atpx',
        .componentSubType = 'test'
    };
    checkResult(AudioOutputUnitPublish(&remoteDesc, (CFStringRef)@"IAATest", 1, _audioUnit), "AudioOutputUnitPublish");
}

- (void)teardownAudioSystem {
    if ( _audioUnit ) {
        checkResult(AudioComponentInstanceDispose(_audioUnit), "AudioComponentInstanceDispose");
        _audioUnit = NULL;
    }
    
    if ( _observerToken ) {
        [[NSNotificationCenter defaultCenter] removeObserver:_observerToken];
        self.observerToken = nil;
    }
}

- (BOOL)stopAudioSystem {
    checkResult(AudioOutputUnitStop(_audioUnit), "AudioOutputUnitStop");
    [[AVAudioSession sharedInstance] setActive:NO error:NULL];
    return YES;
}

- (BOOL)startAudioSystem {
    NSError *error = nil;
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Couldn't activate audio session: %@", error);
        return NO;
    }
    
    if ( !checkResult(AudioOutputUnitStart(_audioUnit), "AudioOutputUnitStart") ) {
        return NO;
    }
    
    return YES;
}

static void audioUnitPropertyChange(void *inRefCon, AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement) {
	__unsafe_unretained AppDelegate *THIS = (__bridge AppDelegate*)inRefCon;
    
    UInt32 interAppAudioConnected = NO;
    UInt32 size = sizeof(interAppAudioConnected);
    OSStatus result = AudioUnitGetProperty(THIS->_audioUnit, kAudioUnitProperty_IsInterAppConnected, kAudioUnitScope_Global, 0, &interAppAudioConnected, &size);
    if ( !checkResult(result, "AudioUnitGetProperty") ) {
        interAppAudioConnected = NO;
    }
    
    if ( interAppAudioConnected ) {
        NSLog(@"IAA connected");
    } else {
        NSLog(@"IAA disconnected");
    }
    
    [THIS updateAudioUnitStatus];
}

#ifdef USE_HARDWARE_SAMPLE_RATE
static void audioUnitStreamFormatChanged(void *inRefCon, AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement) {
    __unsafe_unretained AppDelegate *THIS = (__bridge AppDelegate*)inRefCon;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Read new format
        AudioStreamBasicDescription newFormat;
        UInt32 size = sizeof(newFormat);
        checkResult(AudioUnitGetProperty(THIS->_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &newFormat, &size),
                    "kAudioUnitProperty_StreamFormat");
        
        if ( fabs(THIS->_audioDescription.mSampleRate - newFormat.mSampleRate) > DBL_EPSILON ) {
            NSLog(@"Stream format changed from %lf to %lf",
                  THIS->_audioDescription.mSampleRate, newFormat.mSampleRate);
            
            // Set new format
            THIS->_audioDescription.mSampleRate = newFormat.mSampleRate;
            checkResult(AudioUnitSetProperty(THIS->_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &THIS->_audioDescription, sizeof(THIS->_audioDescription)),
                        "kAudioUnitProperty_StreamFormat");
        }
    });
}
#endif

- (void)updateAudioUnitStatus {
    UInt32 unitConnected;
    UInt32 size = sizeof(unitConnected);
    if ( !checkResult(AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_IsInterAppConnected, kAudioUnitScope_Global, 0, &unitConnected, &size), "AudioUnitGetProperty") ) {
        return;
    }
    
    UInt32 unitRunning;
    size = sizeof(unitRunning);
    if ( !checkResult(AudioUnitGetProperty(_audioUnit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &unitRunning, &size), "AudioUnitGetProperty") ) {
        return;
    }
    
    BOOL foreground = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
    
    BOOL unitShouldBeRunning = unitConnected || foreground;
    
    if ( unitShouldBeRunning ) {
        NSError *error = nil;
        if ( ![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error] ) {
            NSLog(@"Couldn't set audio session category: %@", error);
            return;
        }
        
        if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
            NSLog(@"Couldn't set audio session active: %@", error);
            return;
        }
    }
    
    if ( unitShouldBeRunning ) {
        if ( !unitRunning ) {
            NSLog(@"Starting unit");
            checkResult(AudioOutputUnitStart(_audioUnit), "AudioOutputUnitStart");
        }
    } else {
        if ( unitRunning ) {
            NSLog(@"Stopping unit");
            checkResult(AudioOutputUnitStop(_audioUnit), "AudioOutputUnitStop");
        }
        NSError *error = nil;
        if ( ![[AVAudioSession sharedInstance] setActive:NO error:&error] ) {
            NSLog(@"Couldn't set audio session inactive: %@", error);
            return;
        }
    }
}

static OSStatus audioUnitRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    __unsafe_unretained AppDelegate * THIS = (__bridge AppDelegate*)inRefCon;
    
    // Quick sin-esque oscillator
    const float oscillatorFrequency = 400.0;
    static float oscillatorPosition = 0.0;
    float oscillatorRate = oscillatorFrequency / THIS->_audioDescription.mSampleRate;
    for ( int i=0; i<inNumberFrames; i++ ) {
        float x = oscillatorPosition;
        x *= x; x -= 1.0; x *= x; x -= 0.5; x *= 0.4;
        oscillatorPosition += oscillatorRate;
        if ( oscillatorPosition > 1.0 ) oscillatorPosition -= 2.0;
        ((float*)ioData->mBuffers[0].mData)[i] = x;
        ((float*)ioData->mBuffers[1].mData)[i] = x;
    }
    
    return noErr;
}

@end
