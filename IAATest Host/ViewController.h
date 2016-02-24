//
//  ViewController.h
//  IAATest
//
//  Created by Michael Tyson on 23/10/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AppDelegate;

@interface ViewController : UIViewController
- (IBAction)connect;

@property (weak, nonatomic) AppDelegate * appDelegate;
@property (strong, nonatomic) IBOutlet UIButton *connectButton;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *indicator;
@property (strong, nonatomic) IBOutlet UILabel *label;
@end
