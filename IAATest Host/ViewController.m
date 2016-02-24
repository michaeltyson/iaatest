//
//  ViewController.m
//  IAATest
//
//  Created by Michael Tyson on 23/10/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"

static void * kConnectedChanged = &kConnectedChanged;
static void * kWorkingChanged = &kWorkingChanged;

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.connectButton setTitle:@"Connect" forState:UIControlStateNormal];
    [self.connectButton setTitle:@"Disconnect" forState:UIControlStateSelected];
    
    [self updateState];
}

- (void)setAppDelegate:(AppDelegate *)appDelegate {
    if ( _appDelegate ) {
        [_appDelegate removeObserver:self forKeyPath:@"connected"];
        [_appDelegate removeObserver:self forKeyPath:@"working"];
    }
    
    _appDelegate = appDelegate;
    
    if ( _appDelegate ) {
        [_appDelegate addObserver:self forKeyPath:@"connected" options:0 context:kConnectedChanged];
        [_appDelegate addObserver:self forKeyPath:@"working" options:0 context:kWorkingChanged];
        [self updateState];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == kConnectedChanged || context == kWorkingChanged ) {
        [self updateState];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)updateState {
    self.connectButton.selected = self.appDelegate.connected;
    self.label.text = self.appDelegate.connected ? (self.appDelegate.working ? @"Connecting" : @"Connected")
                                                 : (self.appDelegate.working ? @"Disconnecting" : @"Disconnected");
    self.connectButton.hidden = self.appDelegate.working;
    self.indicator.hidden = !self.appDelegate.working;
    if ( !self.indicator.hidden) {
        [self.indicator startAnimating];
    }
}

- (IBAction)connect {
    self.appDelegate.connected = !self.appDelegate.connected;
}

@end
