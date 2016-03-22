//
//  ViewController.m
//  IAATest
//
//  Created by Michael Tyson on 23/10/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"

@implementation ViewController

- (void)viewDidAppear:(BOOL)animated {
    AppDelegate * appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    self.oscillatorSwitch.on = appDelegate.oscillator;
}

- (IBAction)switchOscillator:(UISwitch *)sender {
    AppDelegate * appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    appDelegate.oscillator = sender.isOn;
}

@end
