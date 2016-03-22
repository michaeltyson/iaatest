//
//  AppDelegate.m
//  IAATest
//
//  Created by Michael Tyson on 19/09/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"
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

static const UInt32 kMaxFramesPerSlice = 4096;

@interface AppDelegate () {
    AudioUnit _audioUnit;
    AudioUnit _iaaNodeUnit;
    AudioStreamBasicDescription _audioDescription;
}
@property (nonatomic, strong) id observerToken;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    ViewController * vc = (ViewController*)application.windows[0].rootViewController;
    vc.appDelegate = self;
    
    [self setupAudioSystem];
    [self startAudioSystem];
    return YES;
}

-(void)dealloc {
    [self teardownAudioSystem];
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
    _audioDescription.mSampleRate        = [AVAudioSession sharedInstance].sampleRate;
    
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &_audioDescription, sizeof(_audioDescription)),
                "kAudioUnitProperty_StreamFormat");
    
    // Set the render callback
    AURenderCallbackStruct rcbs = { .inputProc = audioUnitRenderCallback, .inputProcRefCon = (__bridge void *)(self) };
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &rcbs, sizeof(rcbs)),
                "kAudioUnitProperty_SetRenderCallback");
    
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &kMaxFramesPerSlice, sizeof(kMaxFramesPerSlice)),
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
    
    // Watch for sample rate changes
    checkResult(AudioUnitAddPropertyListener(_audioUnit, kAudioUnitProperty_StreamFormat, audioUnitStreamFormatChanged, (__bridge void*)self), "AudioUnitAddPropertyListener");
    
    self.connected = YES;
}

- (void)setConnected:(BOOL)connected {
    [self setConnected:connected withCompletionBlock:nil];
}

- (void)setConnected:(BOOL)connected withCompletionBlock:(void(^)())block {
    
    if ( _connected == connected ) {
        if ( block ) block();
        return;
    }
    
    _connected = connected;
    
    if ( _connected ) {
        self.working = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            AudioComponentDescription remoteDesc = {
                .componentType = kAudioUnitType_RemoteGenerator,
                .componentManufacturer = 'atpx',
                .componentSubType = 'test'
            };
            
            // Host audio unit
            AudioComponent iaaComponent = AudioComponentFindNext(NULL, &remoteDesc);
            if ( !iaaComponent ) {
                NSLog(@"IAA node not found");
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.connected = NO;
                    self.working = NO;
                    if ( block ) block();
                });
                return;
            }
            
            AudioUnit unit;
            
            BOOL result =
                checkResult(AudioComponentInstanceNew(iaaComponent, &unit), "AudioComponentInstanceNew") &&
                checkResult(AudioUnitAddPropertyListener(unit, kAudioUnitProperty_IsInterAppConnected, audioUnitPropertyChange, (__bridge void*)self),
                        "AudioUnitAddPropertyListener") &&
                checkResult(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &_audioDescription, sizeof(_audioDescription)),
                        "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") &&
                checkResult(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &kMaxFramesPerSlice, sizeof(kMaxFramesPerSlice)),
                        "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice") &&
                checkResult(AudioUnitInitialize(unit), "AudioUnitInitialize");
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( !self.working || _iaaNodeUnit ) {
                    if ( result ) {
                        checkResult(AudioUnitUninitialize(unit), "AudioUnitUninitialize");
                        checkResult(AudioComponentInstanceDispose(unit), "AudioComponentInstanceDispose");
                    }
                } else {
                    self.working = NO;
                    if ( result ) {
                        _iaaNodeUnit = unit;
                    } else {
                        self.connected = NO;
                    }
                }
                if ( block ) block();
            });
        });
    } else {
        if ( _iaaNodeUnit ) {
            self.working = YES;
            AudioUnit unit = _iaaNodeUnit;
            _iaaNodeUnit = NULL;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
                checkResult(AudioUnitUninitialize(unit), "AudioUnitUninitialize");
                checkResult(AudioComponentInstanceDispose(unit), "AudioComponentInstanceDispose");
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.working = NO;
                    if ( block ) block();
                });
            });
        } else {
            self.working = NO;
            if ( block ) block();
        }
    }
}

- (void)teardownAudioSystem {
    if ( _audioUnit ) {
        checkResult(AudioComponentInstanceDispose(_audioUnit), "AudioComponentInstanceDispose");
        _audioUnit = NULL;
    }
    
    if ( _iaaNodeUnit ) {
        checkResult(AudioUnitUninitialize(_iaaNodeUnit), "AudioUnitUninitialize");
        checkResult(AudioComponentInstanceDispose(_iaaNodeUnit), "AudioComponentInstanceDispose");
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
    
    UInt32 interAppAudioConnected = NO;
    UInt32 size = sizeof(interAppAudioConnected);
    OSStatus result = AudioUnitGetProperty(inUnit, kAudioUnitProperty_IsInterAppConnected, kAudioUnitScope_Global, 0, &interAppAudioConnected, &size);
    if ( !checkResult(result, "AudioUnitGetProperty") ) {
        interAppAudioConnected = NO;
    }
    
    if ( interAppAudioConnected ) {
        NSLog(@"IAA connected");
    } else {
        NSLog(@"IAA disconnected");
    }
}

static void audioUnitStreamFormatChanged(void *inRefCon, AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement) {
    __unsafe_unretained AppDelegate *THIS = (__bridge AppDelegate*)inRefCon;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Read new format
        AudioStreamBasicDescription newFormat;
        UInt32 size = sizeof(newFormat);
        checkResult(AudioUnitGetProperty(THIS->_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &newFormat, &size),
                    "kAudioUnitProperty_StreamFormat");
        
        if ( fabs(THIS->_audioDescription.mSampleRate - newFormat.mSampleRate) > DBL_EPSILON ) {
            NSLog(@"Stream format changed from %lf to %lf", THIS->_audioDescription.mSampleRate, newFormat.mSampleRate);
            THIS->_audioDescription.mSampleRate = newFormat.mSampleRate;
            
            if ( THIS->_connected && THIS->_iaaNodeUnit ) {
                // Reconnect
                [THIS setConnected:NO withCompletionBlock:^{
                    // Set new format
                    checkResult(AudioUnitSetProperty(THIS->_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &THIS->_audioDescription, sizeof(THIS->_audioDescription)),
                                "kAudioUnitProperty_StreamFormat");
                    
                    [THIS setConnected:YES];
                }];
            } else {
                checkResult(AudioUnitSetProperty(THIS->_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &THIS->_audioDescription, sizeof(THIS->_audioDescription)),
                            "kAudioUnitProperty_StreamFormat");
            }
        }
    });
}

static OSStatus audioUnitRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    __unsafe_unretained AppDelegate * THIS = (__bridge AppDelegate*)inRefCon;
    
    // Clear buffer
    for ( int i=0; i<ioData->mNumberBuffers; i++ ) {
        memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
    }
    
    if ( THIS->_iaaNodeUnit ) {
        // Draw from the node
        checkResult(AudioUnitRender(THIS->_iaaNodeUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData), "AudioUnitRender");
    }
    
    return noErr;
}

@end
